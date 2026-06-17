#!/bin/sh
# Template. Run from PC where fastboot is available and super backup is in current dir.
set -eu
SUPER_IMG="${1:-super.img}"
adb reboot bootloader || true
fastboot reboot fastboot
fastboot flash super "$SUPER_IMG"
fastboot reboot
