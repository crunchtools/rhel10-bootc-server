FROM registry.redhat.io/rhel10/rhel-bootc

# Setup Repositories
COPY etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10 /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10
COPY etc/yum.repos.d/crunchtools.repo /etc/yum.repos.d/crunchtools.repo
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-crunchtools /etc/pki/rpm-gpg/RPM-GPG-KEY-crunchtools
COPY etc/bashrc.customizations /etc/bashrc.customizations

# Register, update/install, and unregister in ONE layer with a trap so
# unregister+clean run on any exit (constitution II) — no RHSM consumer leaks
# into console.redhat.com inventory as a ghost host. The repo files COPYed above
# do not need registration; only the dnf transaction does.
RUN --mount=type=secret,id=activation_key \
    --mount=type=secret,id=org_id <<'EOF'
set -euo pipefail
subscription-manager register \
    --activationkey="$(cat /run/secrets/activation_key)" \
    --org="$(cat /run/secrets/org_id)"
trap 'subscription-manager unregister || true; subscription-manager clean || true' EXIT
dnf update -y
dnf install -y --nodocs \
    cockpit \
    petit \
    git \
    vim-enhanced \
    nodejs24 \
    python3-pip \
    python3-devel \
    sqlite \
    rsyslog \
    audispd-plugins \
    gh \
    uv \
    sysstat \
    systemd-oomd \
    NetworkManager-wifi \
    wpa_supplicant \
    qemu-kvm \
    qemu-img \
    virtiofsd \
    zram-generator
dnf clean all
rm -rf /var/cache/dnf /var/cache/yum
EOF

# rclone comes from upstream, not EPEL: EPEL's 1.75.2 links
# github.com/andybalholm/brotli v1.2.2 (GO-2026-6888, critical, in KEV), and
# 1.76.0 links 1.2.7 (a1654). The rpm is pinned by its sha256, which is the
# one in the release's SHA256SUMS, signed by rclone's release key
# FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA. Go back to EPEL's package once it
# carries brotli >= 1.2.7. /usr/bin/rclone is bind-mounted into nagios-agent.
# Not RCLONE_*: rclone reads every RCLONE_<FLAG> variable as that flag, and an
# ARG is in the RUN's environment, so RCLONE_VERSION became --version.
ARG RCLONE_RPM_VERSION=1.76.0
ARG RCLONE_RPM_SHA256=a4615495895fec32671c12b45b92f59c60a97fccd3c61a9e02dc3dc2e927a74f
RUN curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --connect-timeout 30 \
        -o /tmp/rclone.rpm \
        "https://github.com/rclone/rclone/releases/download/v${RCLONE_RPM_VERSION}/rclone-v${RCLONE_RPM_VERSION}-linux-amd64.rpm" && \
    echo "${RCLONE_RPM_SHA256}  /tmp/rclone.rpm" | sha256sum -c - && \
    rpm -i /tmp/rclone.rpm && \
    rm -f /tmp/rclone.rpm && \
    test "$(rclone version | head -1)" = "rclone v${RCLONE_RPM_VERSION}"

# Host log forwarding. rsyslog.conf REPLACES the stock RHEL one, which reads
# the journal with imjournal -- that module silently stops following after a
# journal rotation and takes the whole ingest path down with it. Here journald
# forwards to the syslog socket instead and rsyslog only relays onward.
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/systemd/system/rsyslog.service.d/20-collector.conf /etc/systemd/system/rsyslog.service.d/20-collector.conf
COPY etc/systemd/journald.conf.d/10-forward-to-syslog.conf /etc/systemd/journald.conf.d/10-forward-to-syslog.conf
COPY etc/systemd/system/rsyslog.service.d/10-syslog-socket.conf /etc/systemd/system/rsyslog.service.d/10-syslog-socket.conf
COPY etc/containers/containers.conf.d/50-exec-cleanup.conf /etc/containers/containers.conf.d/50-exec-cleanup.conf

# Signed updates (#44, #47). A stolen Quay token could move any tag to any
# image, and every host would run it at the next bootc upgrade or nightly
# podman auto-update. The pipeline signs each promoted digest with cosign;
# these entries make c/image refuse any quay.io/crunchtools image that key did
# not sign -- the bootc image itself and every service image. bootc honours
# them through its default ostree-unverified-registry origin -- do NOT switch
# hosts with --enforce-container-sigpolicy, which refuses any policy whose
# default is insecureAcceptAnything, and that default stays for the other
# registries. The Red Hat entries are kept as the base ships them. The base may
# ship its policy in /etc or only in /usr/share (containers-common 6); the
# merged file goes to /etc, which outranks both.
COPY etc/pki/sigstore/crunchtools-bootc.pub /etc/pki/sigstore/crunchtools-bootc.pub
COPY etc/pki/sigstore/crunchtools-sdlc.pub /etc/pki/sigstore/crunchtools-sdlc.pub
COPY etc/containers/registries.d/crunchtools-bootc.yaml /etc/containers/registries.d/crunchtools-bootc.yaml
RUN python3 -I - <<'EOF'
import json, os
key = "/etc/pki/sigstore/crunchtools-bootc.pub"
sdlc_key = "/etc/pki/sigstore/crunchtools-sdlc.pub"
for k in (key, sdlc_key):
    with open(k) as f:
        assert f.read().startswith("-----BEGIN PUBLIC KEY-----"), k + " is not a PEM public key"
src = next((p for p in ("/etc/containers/policy.json", "/usr/share/containers/policy.json")
            if os.path.exists(p)), None)
assert src, "the base ships no containers policy.json to merge into"
with open(src) as f:
    base = json.load(f)
policy = json.loads(json.dumps(base))
docker = policy.setdefault("transports", {}).setdefault("docker", {})
# cosign signs the repository, not a tag, so only matchRepository accepts it.
# A namespace scope covers every repository under it, each matched to its own
# name.
docker["quay.io/crunchtools"] = [{
    "type": "sigstoreSigned",
    "keyPath": key,
    "signedIdentity": {"type": "matchRepository"},
}]
# sdlc signs its own releases with sdlc's key (bin/sdlc-bootstrap); its :main
# and older releases carry the fleet key. These two scopes take either key and
# still refuse an unsigned image.
for repo in ("sdlc", "sdlc-bootstrap"):
    docker["quay.io/crunchtools/" + repo] = [{
        "type": "sigstoreSigned",
        "keyPaths": [sdlc_key, key],
        "signedIdentity": {"type": "matchRepository"},
    }]
# Only these scopes change: the default and every entry the base shipped
# (the Red Hat keys among them) come through untouched.
added = {"quay.io/crunchtools", "quay.io/crunchtools/sdlc", "quay.io/crunchtools/sdlc-bootstrap"}
assert policy["default"] == base["default"]
for transport, scopes in base.get("transports", {}).items():
    for scope, reqs in scopes.items():
        assert policy["transports"][transport][scope] == reqs, (transport, scope)
assert set(docker) - set(base.get("transports", {}).get("docker", {})) == added
with open("/etc/containers/policy.json", "w") as f:
    json.dump(policy, f, indent=4)
    f.write("\n")
with open("/etc/containers/policy.json") as f:
    assert json.load(f) == policy
EOF

RUN --mount=type=bind,source=tests,target=/run/tests \
    /run/tests/sigpolicy.sh && \
    /run/tests/sigpolicy.sh /etc/containers/policy.json /etc/containers/registries.d

# Backup interlock (RT #1594). `bootc upgrade --apply` reboots this host on its
# own, and it killed a ten-hour pCloud rotation at 93%. The pbs rotations hold
# a block shutdown inhibitor, which logind honours; these two files turn the
# resulting refusal into a deferral instead of a skipped update. The drop-in
# goes to /etc because that is where drop-ins for a unit shipped by another
# package belong; the timer goes to /usr/lib because it comes from the image.
COPY etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf /etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf
COPY etc/systemd/system/bootc-apply-retry.timer /usr/lib/systemd/system/bootc-apply-retry.timer

# The third piece: the drop-in's OnFailure= goes through this service so that a
# DEFERRED apply leaves no failed units while a GENUINE failure stays visible
# (RT #1566). Every deferral cycle used to leave the apply unit failed with
# Result=timeout plus one failed transient per refused reboot, and gloval's
# failed-units check sat CRITICAL for two hours on 2026-11-09 because the
# interlock was working. A check that fires when nothing is wrong gets
# acknowledged; the host had to stop lying about being broken.
#
# Neither this nor the timer is enabled and neither has an [Install] section.
COPY etc/systemd/system/bootc-apply-deferred.service /usr/lib/systemd/system/bootc-apply-deferred.service
COPY etc/libexec/bootc-apply-deferred /usr/libexec/bootc-apply-deferred
COPY etc/libexec/bootc-apply-deferred-testdata /usr/share/bootc-apply-deferred/testdata
RUN chmod 0755 /usr/libexec/bootc-apply-deferred

# All three files, or the interlock has a hole that nothing reports: a missing
# unit makes every OnFailure= a no-op and the deferral silently goes back to
# being a skipped update. 1.2.0 shipped a missing unit exactly this way.
RUN set -e; \
    for f in /usr/lib/systemd/system/bootc-apply-deferred.service \
             /usr/lib/systemd/system/bootc-apply-retry.timer \
             /usr/libexec/bootc-apply-deferred \
             /etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf; do \
        test -e "$f" || { echo "missing from image: $f" >&2; exit 1; }; \
    done; \
    grep -q '^OnFailure=bootc-apply-deferred.service$' \
        /etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf

# The classifier looks for logind's denial over a twenty-minute window, and
# twenty minutes is only the right number between these two settings: it has to
# outlast one cycle (the start timeout plus teardown) and stop short of the
# previous one (the retry interval). Nothing at runtime can notice if one of
# them moves and the window goes stale, so the relationship is asserted here,
# where all three files are in one place.
RUN set -e; \
    grep -q '^TimeoutStartSec=10min$' \
        /etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf; \
    grep -q '^OnActiveSec=30min$' /usr/lib/systemd/system/bootc-apply-retry.timer; \
    grep -q '^CYCLE_WINDOW = "-20min"$' /usr/libexec/bootc-apply-deferred

# Self-test the classifier at build time. It decides when to reset-failed a
# unit, which is to say when to erase the evidence of a failure, and it cannot
# be exercised on the host: reproducing the live case means holding a block
# inhibitor through a real apply and waiting out a ten-minute timeout. The
# fixtures are host states -- the 11-09 refusal, that refusal with the rotation
# already finished, both of logind's refusal wordings, a real exit-code
# failure, the 'signal' result every SUCCESSFUL apply leaves on the way down, a
# timeout where no reboot was ever attempted, a reboot that failed without
# being refused while an unrelated rotation ran, a block inhibitor with nothing
# in the journal, a stale transient, a failed transient belonging to something
# else, and a deferral that must clear one while leaving the other. Each one
# carries the decision it must produce.
RUN /usr/libexec/bootc-apply-deferred --self-test \
        /usr/share/bootc-apply-deferred/testdata

# Wi-Fi watchdog (a301): re-activates a Wi-Fi connection whose gateway stops
# answering while NM still calls it connected, which is how an AP channel
# switch took exedore off the network on 2026-11-18. Enabled for every host;
# the timer starts only where /etc/sysconfig/wifi-watchdog names a connection
# (install/wifi.ks.example writes it), so a wired host never runs it.
COPY etc/libexec/wifi-watchdog /usr/libexec/wifi-watchdog
COPY etc/systemd/system/wifi-watchdog.service /usr/lib/systemd/system/wifi-watchdog.service
COPY etc/systemd/system/wifi-watchdog.timer /usr/lib/systemd/system/wifi-watchdog.timer
RUN chmod 0755 /usr/libexec/wifi-watchdog && systemctl enable wifi-watchdog.timer
RUN --mount=type=bind,source=tests,target=/run/tests \
    --mount=type=bind,source=install,target=/run/install \
    /run/tests/wifi-watchdog.sh /usr/libexec/wifi-watchdog && \
    /run/tests/wifi-ks.sh /run/install/wifi.ks.example

# Create node/npm/npx symlinks
RUN ln -s /usr/bin/node-24 /usr/bin/node && \
    ln -s /usr/bin/npm-24 /usr/bin/npm && \
    ln -s /usr/bin/npx-24 /usr/bin/npx

# System configuration
RUN systemctl set-default multi-user.target && \
    systemctl enable cockpit.socket podman-auto-update.timer fstrim.timer \
        systemd-oomd.service \
        sysstat.service \
        rsyslog.service && \
    ln -s /usr/lib/systemd/system/rsyslog.service /etc/systemd/system/syslog.service && \
    ln -s /usr/share/zoneinfo/America/New_York /etc/localtime && \
    cat /etc/bashrc.customizations >> /etc/bashrc && \
    ln -s /usr/bin/fusermount3 /usr/bin/fusermount && \
    rm -f /etc/motd.d/insights-client

# Log forwarding reaches RSYSLOG_COLLECTOR, end to end (tests/forward-target.sh).
# rsyslogd -N1 passed a version of this that forwarded nowhere.
RUN --mount=type=bind,source=tests,target=/run/tests \
    /run/tests/forward-target.sh

# Clean up (RHSM unregister happens via the trap in the dnf layer above)
RUN rm -rf /var/run \
    /var/log/*.log \
    /var/log/dnf* \
    /var/log/hawkey* \
    /var/log/rhsm/* \
    /tmp/* \
    /var/tmp/* \
    /root/.cache

# Remove old kernel to satisfy bootc lint (dnf update may pull a newer one)
RUN cd /usr/lib/modules && ls | sort -V | head -n -1 | xargs -I{} rm -rf {}

# Final lint step to prevent easy-to-catch issues at build time
RUN bootc container lint
