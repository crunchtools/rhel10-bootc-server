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
COPY etc/bashrc.customizations /etc/bashrc.customizations

# Combined dnf operations: update and install in one layer with --nodocs
RUN dnf update -y && \
    dnf install -y --nodocs \
        cockpit \
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
