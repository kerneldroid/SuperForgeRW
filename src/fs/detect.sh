#!/bin/bash

detect_fs_type() {
    local img="$1" bt
    erofs -i "$img" &>>$LOG && { echo erofs; return 0; }
    tune2fs -l "$img" &>>$LOG && { echo ext4; return 0; }
    bt="$(blkid "$img" 2>/dev/null | sed -n 's|.*TYPE="\([^"]*\)".*|\1|p' | head -n1 | tr '[:upper:]' '[:lower:]')"
    case "$bt" in
    ext4|erofs|f2fs) echo "$bt"; return 0 ;;
    esac
    detect_f2fs_magic "$img" && { echo f2fs; return 0; }
    echo unknown
    return 1
}

detect_f2fs_magic() {
    local magic
    magic="$(busybox od -An -tx1 -N4 -j1024 "$1" 2>/dev/null | tr -d ' \n')"
    [ "$magic" = "1020f5f2" ]
}

normalize_fs_value() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    f2fs) echo f2fs ;;
    ext4|*) echo ext4 ;;
    esac
}

target_fs_for_source() {
    case "$1" in
    erofs) normalize_fs_value "$TARGET_FS_FROM_EROFS" ;;
    ext4) normalize_fs_value "$TARGET_FS_FROM_EXT4" ;;
    f2fs) normalize_fs_value "$TARGET_FS_FROM_F2FS" ;;
    *) normalize_fs_value "$TARGET_FS_FROM_OTHER" ;;
    esac
}

f2fs_target_policy_requested() {
    [ "$(normalize_fs_value "$TARGET_FS_FROM_EXT4")" = "f2fs" ] && return 0
    [ "$(normalize_fs_value "$TARGET_FS_FROM_EROFS")" = "f2fs" ] && return 0
    [ "$(normalize_fs_value "$TARGET_FS_FROM_F2FS")" = "f2fs" ] && return 0
    [ "$(normalize_fs_value "$TARGET_FS_FROM_OTHER")" = "f2fs" ] && return 0
    return 1
}

