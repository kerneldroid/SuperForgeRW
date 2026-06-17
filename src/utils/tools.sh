#!/bin/bash

resolve_tool() {
    local n d
    # Order matters: user-provided drop-in tools override recovery tools.
    for d in         /sdcard/F2FS_TOOLS         /data/media/0/F2FS_TOOLS         /data/local/tmp/f2fs_tools         "$TMP_NEO/tools/f2fs_tools"         "$TMP_NEO/$arch"         /system/bin /system/xbin /vendor/bin /sbin /bin /usr/bin; do
        [ -d "$d" ] || continue
        for n in "$@"; do
            [ -x "$d/$n" ] && { echo "$d/$n"; return 0; }
        done
    done
    for n in "$@"; do
        command -v "$n" 2>/dev/null && return 0
    done
    return 1
}

load_f2fs_tools() {
    [ -n "$F2FS_MKFS_BIN" ] || F2FS_MKFS_BIN="$(resolve_tool make_f2fs mkfs.f2fs)"
    [ -n "$F2FS_SLOAD_BIN" ] || F2FS_SLOAD_BIN="$(resolve_tool sload_f2fs sload.f2fs)"
    [ -n "$F2FS_RESIZE_BIN" ] || F2FS_RESIZE_BIN="$(resolve_tool resize.f2fs)"
    [ -n "$F2FS_FSCK_BIN" ] || F2FS_FSCK_BIN="$(resolve_tool fsck.f2fs)"
    echo "F2FS tools: mkfs=$F2FS_MKFS_BIN sload=$F2FS_SLOAD_BIN resize=$F2FS_RESIZE_BIN fsck=$F2FS_FSCK_BIN" &>>$LOG
}

require_f2fs_tools() {
    load_f2fs_tools
    [ -n "$F2FS_MKFS_BIN" ] || {
        my_print "F2FS target requested, but make_f2fs/mkfs.f2fs was not found in recovery PATH or bundled tools"
        abortF 73 2201
    }
    if is_true "$REQUIRE_F2FS_TOOLS"; then
        [ -n "$F2FS_RESIZE_BIN" ] || {
            my_print "resize.f2fs not found; continuing in no-resize F2FS mode. Images will be created at final size."
            echo "F2FS no-resize mode active: resize.f2fs missing, so later F2FS expand requests are skipped" &>>$LOG
        }
        case "$F2FS_POPULATE_MODE" in
        sload|auto|"")
            [ -n "$F2FS_SLOAD_BIN" ] || {
                if is_true "${ALLOW_F2FS_MOUNTCOPY_FALLBACK:-false}"; then
                    my_print "sload_f2fs not found; unsafe F2FS mount-copy fallback allowed by config"
                else
                    my_print "F2FS target requested, but sload_f2fs/sload.f2fs was not found. Bundled or recovery sload is required."
                    abortF 73 2203
                fi
            }
            ;;
        mountcopy)
            is_true "${ALLOW_F2FS_MOUNTCOPY_FALLBACK:-false}" || {
                my_print "F2FS_POPULATE_MODE=mountcopy is blocked by safe mode. Set ALLOW_F2FS_MOUNTCOPY_FALLBACK=true only for debugging."
                abortF 73 2204
            }
            ;;
        esac
    fi
}

set_file_size() {
    local file="$1" size="$2"
    rm -f "$file" &>>$LOG
    truncate -s "$size" "$file" &>>$LOG || \
    busybox truncate -s "$size" "$file" &>>$LOG || \
    dd if=/dev/zero of="$file" bs=1 count=0 seek="$size" &>>$LOG
}

