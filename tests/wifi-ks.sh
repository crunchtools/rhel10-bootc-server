#!/bin/bash
# Build-time test: wifi.ks.example's %post writes the watchdog config, keeps a
# profile Anaconda already copied, writes one when it did not, and treats the
# SSID as data (a301).
#
# The %post is rendered with an SSID carrying a quote, a $( ), a regex dot and
# a / that cannot go in a file name, its /etc paths moved under a scratch root,
# and run with restorecon stubbed.
set -euo pipefail

KS=${1:-install/wifi.ks.example}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
printf '#!/bin/sh\n' > "$W/bin/restorecon"
chmod 0755 "$W/bin/restorecon"

SSID="it's \$(touch PWNED) a.b/c"
FILE="it's \$(touch PWNED) a.b_c.nmconnection"
render() {
    local line
    awk '/^%post/{p=1; next} /^%end/{p=0} p' "$KS" | while IFS= read -r line; do
        line=${line//@SSID@/$SSID}
        line=${line//@PSK@/secret-psk}
        printf '%s\n' "${line//\/etc\//$1/etc/}"
    done > "$1.sh"
}
check() { [ "$2" = "$3" ] || { echo "FAIL: $1: expected '$3', got '$2'"; exit 1; }; echo "PASS: $1"; }
run() { mkdir -p "$1/etc/sysconfig"; render "$1"; (cd "$W" && PATH="$W/bin:$PATH" bash "$1.sh"); }

R="$W/fresh"; run "$R"
check "the watchdog config names the SSID" "$(cat "$R/etc/sysconfig/wifi-watchdog")" "WIFI_WATCHDOG_CONNECTION=$SSID"
check "one profile written when none was copied" "$(ls "$R/etc/NetworkManager/system-connections")" "$FILE"
check "the profile's id is the SSID" "$(sed -n 's/^id=//p' "$R/etc/NetworkManager/system-connections/$FILE")" "$SSID"
check "the profile is 0600" "$(stat -c %a "$R/etc/NetworkManager/system-connections/$FILE")" 600

R="$W/copied"; mkdir -p "$R/etc/NetworkManager/system-connections"
printf '[wifi]\nssid=%s\n' "$SSID" > "$R/etc/NetworkManager/system-connections/anaconda.nmconnection"
run "$R"
check "a copied profile is kept and not duplicated" "$(ls "$R/etc/NetworkManager/system-connections")" "anaconda.nmconnection"
check "the watchdog config is written either way" "$(cat "$R/etc/sysconfig/wifi-watchdog")" "WIFI_WATCHDOG_CONNECTION=$SSID"

R="$W/lookalike"; mkdir -p "$R/etc/NetworkManager/system-connections"
printf '[wifi]\nssid=%s\n' "${SSID/a.b/aXb}" > "$R/etc/NetworkManager/system-connections/other.nmconnection"
run "$R"
check "a regex look-alike SSID is not mistaken for ours" "$(ls "$R/etc/NetworkManager/system-connections" | wc -l)" 2

[ ! -e "$W/PWNED" ] || { echo "FAIL: the SSID was executed as shell"; exit 1; }
echo "PASS: the SSID is never executed"
