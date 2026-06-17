#!/system/bin/sh
# Run from recovery adb shell if bootloop is caused by the Magisk module layer.
MOD1=/data/adb/modules/SuperForgeRW
MOD2=/data/adb/modules/RO2RW
mkdir -p "$MOD1" 2>/dev/null
touch "$MOD1/disable" 2>/dev/null
[ -d "$MOD2" ] && touch "$MOD2/disable" 2>/dev/null
echo "SuperForgeRW/RO2RW module disable markers written. Reboot now."
