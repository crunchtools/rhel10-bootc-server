FROM registry.redhat.io/rhel10/rhel-bootc

# Register with RHSM using activation key (secrets mounted at build time, never in image layers)
RUN --mount=type=secret,id=activation_key \
    --mount=type=secret,id=org_id \
    subscription-manager register \
        --activationkey=$(cat /run/secrets/activation_key) \
        --org=$(cat /run/secrets/org_id)

# Setup Repositories
COPY etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10 /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-10
COPY etc/yum.repos.d/crunchtools.repo /etc/yum.repos.d/crunchtools.repo
COPY etc/pki/rpm-gpg/RPM-GPG-KEY-crunchtools /etc/pki/rpm-gpg/RPM-GPG-KEY-crunchtools
COPY etc/bashrc.customizations /etc/bashrc.customizations

# Combined dnf operations: update and install in one layer with --nodocs
RUN dnf update -y && \
    dnf install -y --nodocs \
        cockpit \
        petit \
        git \
        vim-enhanced \
        nodejs24 \
        python3-pip \
        python3-devel \
        sqlite \
        rclone \
        rsyslog \
        gh \
        uv \
        sysstat \
        systemd-oomd && \
    dnf clean all && \
    rm -rf /var/cache/dnf /var/cache/yum

# Host log forwarding. rsyslog.conf REPLACES the stock RHEL one, which reads
# the journal with imjournal -- that module silently stops following after a
# journal rotation and takes the whole ingest path down with it. Here journald
# forwards to the syslog socket instead and rsyslog only relays onward.
COPY etc/rsyslog.conf /etc/rsyslog.conf
COPY etc/systemd/journald.conf.d/10-forward-to-syslog.conf /etc/systemd/journald.conf.d/10-forward-to-syslog.conf
COPY etc/systemd/system/rsyslog.service.d/10-syslog-socket.conf /etc/systemd/system/rsyslog.service.d/10-syslog-socket.conf
COPY etc/containers/containers.conf.d/50-exec-cleanup.conf /etc/containers/containers.conf.d/50-exec-cleanup.conf

# Backup interlock (RT #1594). `bootc upgrade --apply` reboots this host on its
# own, and it killed a ten-hour pCloud rotation at 93%. The pbs rotations hold
# a block shutdown inhibitor, which logind honours; these two files turn the
# resulting refusal into a deferral instead of a skipped update. The drop-in
# goes to /etc because that is where drop-ins for a unit shipped by another
# package belong; the timer goes to /usr/lib because it comes from the image.
COPY etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf /etc/systemd/system/bootc-fetch-apply-updates.service.d/10-defer-for-backups.conf
COPY etc/systemd/system/bootc-apply-retry.timer /usr/lib/systemd/system/bootc-apply-retry.timer

# linux-mcp-server: host administration for the Josui Prime agent, reached
# only through the Trentina gateway (RT#1568). It is in the image rather than
# installed by hand because /usr and /opt are read-only here and because the
# one service that exists to repair this host should survive rebuilding it.
#
# Pinned. This runs as root, and a floating version is not a thing to find out
# about at boot.
#
# Not enabled: it needs /etc/linux-mcp-server/linux-mcp.env, which holds the
# gatekeeper API key and is per-host, so the unit carries a ConditionPathExists
# and a host without that file simply does not start it.
RUN UV_TOOL_DIR=/usr/lib/linux-mcp-server UV_TOOL_BIN_DIR=/usr/bin \
        uv tool install linux-mcp-server==1.8.0 && \
    rm -rf /root/.cache

COPY etc/linux-mcp-server/policy.yaml /etc/linux-mcp-server/policy.yaml
# Source lives under etc/ so the build workflow's paths filter sees it; the
# destination is /usr/lib because this unit comes from the image, not the host.
COPY etc/systemd/system/linux-mcp-server.service /usr/lib/systemd/system/linux-mcp-server.service
COPY etc/libexec/linux-mcp-server-preflight /usr/libexec/linux-mcp-server-preflight
COPY etc/libexec/testdata /usr/share/linux-mcp-server/testdata
RUN chmod 0755 /usr/libexec/linux-mcp-server-preflight

# Everything this feature needs is in the image. A COPY lost in an edit
# produces a host where the binary and its config are present, the service
# simply does not exist, and nothing says so until someone asks systemd for
# it -- which is how 1.2.0 shipped.
RUN set -e; \
    for f in /usr/bin/linux-mcp-server \
             /usr/lib/systemd/system/linux-mcp-server.service \
             /usr/libexec/linux-mcp-server-preflight \
             /etc/linux-mcp-server/policy.yaml; do \
        test -e "$f" || { echo "missing from image: $f" >&2; exit 1; }; \
    done

# Parse the authorization policy with upstream's own parser. get_policy()
# raises on a malformed file at the first call, and on the http transport a
# policy that will not load is deny-everything -- which would be discovered on
# the day this host needed repairing. Upstream's tests already cover the
# localhost-grant and wildcard-deny semantics; this only proves our file loads.
RUN /usr/lib/linux-mcp-server/linux-mcp-server/bin/python -c \
    'from pathlib import Path; from linux_mcp_server.auth_policy import AuthPolicy; \
     p = AuthPolicy.from_yaml(Path("/etc/linux-mcp-server/policy.yaml")); \
     assert len(p.rules) == 2, p.rules'

# Self-test the preflight at build time. It is access control in a script:
# the IPv6 unspecified address has enough spellings that "looks right" is not
# evidence, and the fence check is the thing standing between this port and
# every container on the bridge. The fixtures are nftables' own JSON, taken
# from the live table and then broken eleven ways; they stay in the image so
# the same check can be re-run on a host.
RUN set -e; \
    export LINUX_MCP_PORT=8034 LINUX_MCP_ALLOW_FROM=10.89.0.89 LINUX_MCP_ALLOW_IF=podman1; \
    T=/usr/share/linux-mcp-server/testdata; \
    LINUX_MCP_HOST=10.0.0.1 /usr/libexec/linux-mcp-server-preflight --bind-only; \
    for bad in 0.0.0.0 :: ::0 0:0:0:0:0:0:0:0 not-an-ip ""; do \
        if LINUX_MCP_HOST="$bad" /usr/libexec/linux-mcp-server-preflight --bind-only 2>/dev/null; then \
            echo "preflight accepted a bind address it must refuse: '$bad'" >&2; exit 1; \
        fi; \
    done; \
    export LINUX_MCP_HOST=10.89.0.1; \
    /usr/libexec/linux-mcp-server-preflight --table-json "$T/fence-good.json"; \
    for bad in accept-any-source accept-range drop-first drop-conditional \
               drop-off-hook drop-one-address drop-other-source drop-udp \
               extra-rule no-accept no-drop; do \
        if /usr/libexec/linux-mcp-server-preflight --table-json "$T/fence-$bad.json" 2>/dev/null; then \
            echo "preflight accepted a firewall table it must refuse: $bad" >&2; exit 1; \
        fi; \
    done

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

# Unregister from RHSM and clean up
RUN subscription-manager unregister && \
    rm -rf /var/run \
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
