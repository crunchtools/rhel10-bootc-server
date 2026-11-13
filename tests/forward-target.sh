#!/bin/bash
# Build-time test: the forwarder ships to RSYSLOG_COLLECTOR, end to end.
#
# rsyslogd -N1 is not enough here. The target is expanded by a backtick in
# rsyslog.conf, and the first version of this change (a `cat` of a file)
# passed -N1 while sending to "127.0.0.1 " -- a trailing newline turned into a
# space that never resolved. So this sends a real message through the shipped
# rsyslog.conf and checks it arrives where the variable says, for both the
# image default (from the drop-in) and a host override (an EnvironmentFile).
set -euo pipefail

CONF=/etc/rsyslog.conf
DROPIN=/etc/systemd/system/rsyslog.service.d/20-collector.conf
W=$(mktemp -d)
trap 'kill $(cat "$W"/*.pid 2>/dev/null) 2>/dev/null || true; rm -rf "$W"' EXIT

# The default, read the way systemd would: from the drop-in's Environment=.
default=$(sed -n 's/^Environment=RSYSLOG_COLLECTOR=//p' "$DROPIN")
[ "$default" = "127.0.0.1" ] || { echo "FAIL: drop-in default is '$default'"; exit 1; }
grep -q '^EnvironmentFile=-/etc/sysconfig/rsyslog-collector$' "$DROPIN" \
    || { echo "FAIL: drop-in does not read the host override"; exit 1; }

# The shipped config, with its inputs swapped for a private socket and its
# port moved off 514 (nothing in a build may bind that). Everything about the
# forward action -- the backtick target included -- is the real one.
#
# libcapng.enable="off" in both test daemons only: rsyslog drops capabilities
# at startup and aborts when the kernel refuses (capng_apply=-4), which a
# build sandbox's partial capability set does. The shipped config keeps it.
sender_conf() {
    sed -e "s#global(workDirectory=\"/var/lib/rsyslog\"#global(libcapng.enable=\"off\" workDirectory=\"$W/$1\"#" \
        -e "s#queue.spoolDirectory=\"/var/lib/rsyslog\"#queue.spoolDirectory=\"$W/$1\"#" \
        -e 's#module(load="imuxsock" SysSock.Use="on")#module(load="imuxsock" SysSock.Use="off")#' \
        -e 's#port="514"#port="10514"#' "$CONF"
    echo "input(type=\"imuxsock\" Socket=\"$W/$1/log.sock\")"
}

# probe <name> <listen address> <RSYSLOG_COLLECTOR value>
probe() {
    local n=$1 addr=$2 target=$3
    mkdir -p "$W/$n" "$W/$n-rx"
    cat > "$W/$n-rx/rx.conf" <<RX
global(workDirectory="$W/$n-rx" libcapng.enable="off")
module(load="imtcp")
input(type="imtcp" address="$addr" port="10514")
template(name="m" type="string" string="%msg%\n")
:msg, contains, "probe-$n" action(type="omfile" file="$W/$n-rx/got" template="m")
RX
    sender_conf "$n" > "$W/$n/tx.conf"
    rsyslogd -f "$W/$n-rx/rx.conf" -i "$W/$n-rx.pid"
    RSYSLOG_COLLECTOR="$target" rsyslogd -f "$W/$n/tx.conf" -i "$W/$n.pid"
    for _ in $(seq 20); do [ -S "$W/$n/log.sock" ] && break; sleep 0.25; done
    logger -u "$W/$n/log.sock" "probe-$n"
    for _ in $(seq 40); do grep -q "probe-$n" "$W/$n-rx/got" 2>/dev/null && break; sleep 0.25; done
    if grep -q "probe-$n" "$W/$n-rx/got" 2>/dev/null; then
        echo "PASS: $n reached $addr"
    else
        echo "FAIL: $n did not reach $addr"; exit 1
    fi
}

probe default "$default" "$default"

# A host override, parsed as an EnvironmentFile line would be: comments allowed.
printf '# overlay host\nRSYSLOG_COLLECTOR=127.0.0.2\n' > "$W/override.env"
override=$(sed -n 's/^RSYSLOG_COLLECTOR=//p' "$W/override.env")
probe override 127.0.0.2 "$override"
