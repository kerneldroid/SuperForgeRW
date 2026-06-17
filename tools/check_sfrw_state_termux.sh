#!/system/bin/sh
# Quick Termux/root state check for SuperForgeRW Nexus.
# Usage: su -c sh check_sfrw_state_termux.sh

echo "== BASIC =="
echo "release=$(getprop ro.build.version.release) sdk=$(getprop ro.build.version.sdk)"
echo "brand=$(getprop ro.product.brand) model=$(getprop ro.product.model) device=$(getprop ro.product.device)"
echo "slot=$(getprop ro.boot.slot_suffix) virtual_ab=$(getprop ro.virtual_ab.enabled) ab_update=$(getprop ro.build.ab_update)"
echo "vbstate=$(getprop ro.boot.verifiedbootstate) device_state=$(getprop ro.boot.vbmeta.device_state) flash_locked=$(getprop ro.boot.flash.locked)"

echo "\n== BOOTCTL SNAPSHOT =="
bootctl get-snapshot-merge-status 2>/dev/null || /system/bin/bootctl get-snapshot-merge-status 2>/dev/null || echo "bootctl snapshot status unavailable"

echo "\n== MAPPER COW/SNAPSHOT =="
ls /dev/block/mapper 2>/dev/null | grep -Ei 'cow|snapshot' || echo "no mapper cow/snapshot entries"

echo "\n== LPDUMP COW/SNAPSHOT =="
slot="$(getprop ro.boot.slot_suffix | tr -d _)"
if command -v lpdump >/dev/null 2>&1; then
  lpdump --slot="$slot" 2>/dev/null | grep -Ei 'Update state|Using snapuserd|Group: cow|Name: .*cow|snapshot' || true
elif [ -x /system/bin/lpdump ]; then
  /system/bin/lpdump --slot="$slot" 2>/dev/null | grep -Ei 'Update state|Using snapuserd|Group: cow|Name: .*cow|snapshot' || true
else
  echo "lpdump unavailable"
fi

echo "\n== METADATA SNAPSHOT DIR =="
ls -la /metadata/ota /metadata/ota/snapshots 2>/dev/null || true
