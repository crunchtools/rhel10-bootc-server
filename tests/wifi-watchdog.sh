#!/bin/bash
# Build-time test: wifi-watchdog counts misses, re-activates at the threshold,
# honours the holdoff, and resets when the gateway answers (a301).
#
# The script is run as shipped, with ping and nmcli replaced by stubs on PATH:
# the stub ping succeeds or fails on a flag file, and the stub nmcli reports
# a fixed device and gateway and appends every `connection up` to a log.
set -euo pipefail

SCRIPT=${1:-/usr/libexec/wifi-watchdog}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/state"

cat > "$W/bin/ping" <<EOF
#!/bin/bash
[ -e "$W/gw-up" ]
EOF
cat > "$W/bin/nmcli" <<EOF
#!/bin/bash
case "\$*" in
    *"-g GENERAL.DEVICES connection show testcon") [ -e "$W/inactive" ] || echo wlan0 ;;
    *"-g IP4.GATEWAY connection show testcon")     [ -e "$W/inactive" ] || echo 192.0.2.1 ;;
    *"connection up testcon")                      echo up >> "$W/ups"; echo "Connection successfully activated" ;;
    *) echo "unexpected nmcli \$*" >&2; exit 2 ;;
esac
EOF
chmod 0755 "$W/bin/ping" "$W/bin/nmcli"

run() {
    PATH="$W/bin:$PATH" STATE_DIRECTORY="$W/state" \
        WIFI_WATCHDOG_CONNECTION=testcon WIFI_WATCHDOG_FAILURES=3 \
        WIFI_WATCHDOG_HOLDOFF=300 "$SCRIPT" > "$W/out"
}
ups() { [ -e "$W/ups" ] && wc -l < "$W/ups" || echo 0; }
check() { [ "$2" = "$3" ] || { echo "FAIL: $1: expected '$3', got '$2'"; cat "$W/out"; exit 1; }; echo "PASS: $1"; }

touch "$W/gw-up"; run
check "a healthy gateway does nothing" "$(ups)" 0

rm "$W/gw-up"; run; run
check "two misses stay under the threshold" "$(ups)" 0
check "the miss is logged as a warning" "$(head -c 3 "$W/out")" "<4>"
run
check "the third miss re-activates" "$(ups)" 1

run; run; run
check "the holdoff blocks a second re-activation" "$(ups)" 1
grep -q "held off" "$W/out" || { echo "FAIL: holdoff not logged"; exit 1; }
echo "PASS: holdoff logged"

echo $(( $(date +%s) - 301 )) > "$W/state/last_action"
echo 2 > "$W/state/failures"; run
check "after the holdoff it re-activates again" "$(ups)" 2

echo 2 > "$W/state/failures"; touch "$W/gw-up"; run
check "an answer resets the count" "$(cat "$W/state/failures")" 0
grep -q "answering again" "$W/out" || { echo "FAIL: recovery not logged"; exit 1; }
echo "PASS: recovery logged"

rm -f "$W/gw-up" "$W/state/last_action"; touch "$W/inactive"; run; run; run
check "an inactive connection counts as a miss" "$(ups)" 3

if PATH="$W/bin:$PATH" STATE_DIRECTORY="$W/state" "$SCRIPT" > "$W/out" 2>&1; then
    echo "FAIL: ran without WIFI_WATCHDOG_CONNECTION"; exit 1
fi
echo "PASS: refuses to run unconfigured"
