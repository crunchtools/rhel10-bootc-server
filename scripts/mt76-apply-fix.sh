#!/bin/bash
# Apply 20b126920a25 to a kernel source tree, or refuse loudly (RT#1656).
#
#   apply-fix.sh PATCH TREE [KVER]
#
# Refuses when the tree already carries the fix (the patch reverse-applies):
# RHEL has caught up and the overlay should be deleted (kmod/mt76/README.md,
# REMOVING). Refuses when the patch does not apply: a wireless rebase moved
# mt76_sta_add and the patch needs a rebase. git apply allows no fuzz, so a
# near miss is a refusal too.
set -euo pipefail

patch=$1
tree=$2
kver=${3:-this kernel}

cd "$tree"
if git apply -p1 -R --check "$patch" 2>/dev/null; then
    echo "${kver} already carries 20b126920a25: remove the overlay, every piece listed under REMOVING in kmod/mt76/README.md" >&2
    exit 1
fi
if ! git apply -p1 --check "$patch"; then
    echo "20b126920a25 does not apply to ${kver}'s mt76: rebase kmod/mt76 or drop the overlay" >&2
    exit 1
fi
git apply -p1 "$patch"
