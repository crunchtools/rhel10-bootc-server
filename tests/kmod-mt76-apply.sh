#!/bin/bash
# Build-time test: scripts/mt76-apply-fix.sh patches an unpatched mt76_sta_add,
# and refuses a tree that already has the fix and one the patch does not fit
# (RT#1656). The fixture is mt76_sta_add from c10s kernel-6.12.0-284.el10.
#
#   kmod-mt76-apply.sh APPLY_FIX PATCH FIXTURE_ROOT
set -euo pipefail

apply=$1
patch=$2
fixture=$3
src=drivers/net/wireless/mediatek/mt76/mac80211.c
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

cp -r "$fixture" "$W/unpatched"
"$apply" "$patch" "$W/unpatched" || fail "an unpatched tree was refused"
grep -q 'published = rcu_dereference_protected' "$W/unpatched/$src" || fail "the fix is not in the patched tree"
pass "an unpatched mt76_sta_add takes the fix"

if "$apply" "$patch" "$W/unpatched" 2>"$W/err"; then
    fail "a tree that already has the fix was patched again"
fi
grep -q 'already carries 20b126920a25' "$W/err" || fail "the already-fixed refusal says: $(cat "$W/err")"
pass "a tree that already has the fix is refused"

cp -r "$fixture" "$W/moved"
sed -i '/ewma_signal_init(&wcid->rssi);/d' "$W/moved/$src"
if "$apply" "$patch" "$W/moved" 2>"$W/err"; then
    fail "a tree the patch does not fit was patched"
fi
grep -q 'does not apply' "$W/err" || fail "the no-fit refusal says: $(cat "$W/err")"
pass "a tree the patch does not fit is refused"
