#!/bin/bash
# Build-time test: the mt76 overlay (RT#1656, a342) is what the image's kernel
# loads. Every module of the mt7925e stack resolves under updates/mt76 for the
# one kernel in the image, carries that kernel's vermagic, and mt76.ko (the
# module the patch touches) has a different srcversion from the stock one
# (RHEL builds with CONFIG_MODULE_SRCVERSION_ALL=y). The initramfs must not
# hold an mt76 module, or the stock driver would load before the root switch.
set -euo pipefail

fail() { echo "kmod-mt76: $*" >&2; exit 1; }

kver=$(ls /usr/lib/modules)
[ "$(echo "$kver" | wc -l)" = 1 ] || fail "more than one kernel: $kver"

for m in mt76 mt76-connac-lib mt792x-lib mt7925-common mt7925e; do
    file=$(modinfo -k "$kver" -F filename "$m")
    [[ $file == "/usr/lib/modules/$kver/updates/mt76/"* ]] || fail "$m resolves to $file, not the overlay"
    magic=$(modinfo -k "$kver" -F vermagic "$m")
    [[ $magic == "$kver "* ]] || fail "$m has vermagic '$magic', not $kver"
    echo "$m -> $file"
done

stock_files=("/usr/lib/modules/$kver/kernel/drivers/net/wireless/mediatek/mt76/mt76.ko"*)
[ -e "${stock_files[0]}" ] || fail "no stock mt76 module to compare against"
stock=$(modinfo -F srcversion "${stock_files[0]}")
ours=$(modinfo -k "$kver" -F srcversion mt76)
if [ -z "$stock" ] || [ -z "$ours" ]; then
    fail "no srcversion to compare (stock '$stock', overlay '$ours')"
fi
[ "$stock" != "$ours" ] || fail "overlay mt76 has the stock srcversion $stock: built from unpatched source"
echo "mt76 srcversion: stock $stock, overlay $ours"

initramfs=/usr/lib/modules/$kver/initramfs.img
if [ -e "$initramfs" ]; then
    listing=$(lsinitrd "$initramfs")
    [ -n "$listing" ] || fail "lsinitrd listed nothing in $initramfs"
    if grep -q '/mt76/' <<<"$listing"; then
        fail "$initramfs carries mt76 modules; the stock driver would load first"
    fi
fi
