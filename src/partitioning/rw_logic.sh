#!/bin/bash

is_reclaim_partition() {
    # Optional GSI-space reclaim mode for OPlus/Realme dynamic "my_*" payloads.
    # Default is OFF. When ON, matching partitions are excluded from rebuilt super,
    # not converted/mounted, and not preserved raw. Snapshot/COW state still blocks.
    local p="$1" r
    is_true "$OPLUS_RECLAIM_MODE" || return 1
    is_snapshot_partition "$p" && return 1
    [ -n "${RECLAIM_PARTITIONS:-}" ] || return 1
    set -f
    part_match_list "$p" $RECLAIM_PARTITIONS
    r=$?
    set +f
    [ "$r" = "0" ] || return 1
    case "$(part_base_name "$p")" in
    my_manifest)
        is_true "$RECLAIM_INCLUDE_MY_MANIFEST" || return 1
        ;;
    esac
    echo "Reclaim-mode drop partition $p" &>>$LOG
    return 0
}

list_reclaim_partition_candidates() {
    for p in $(list_lpdump_partition_names); do
        is_snapshot_partition "$p" && continue
        part_matches_slot "$p" || continue
        is_reclaim_partition "$p" && echo "$p"
    done | busybox awk '!seen[$0]++'
}

is_rw_candidate_partition() {
    local p="$1" r
    is_snapshot_partition "$p" && return 1
    set -f
    part_match_list "$p" $DENY_PARTITIONS
    r=$?
    set +f
    [ "$r" = "0" ] && {
        echo "Preserve-only partition $p by denylist" &>>$LOG
        return 1
    }
    [ -n "${ALLOW_PARTITIONS:-}" ] && {
        set -f
        part_match_list "$p" $ALLOW_PARTITIONS
        r=$?
        set +f
        [ "$r" = "0" ] && return 0
        echo "Preserve-only partition $p not in allowlist" &>>$LOG
        return 1
    }
    return 0
}

list_rw_candidate_partitions() {
    for p in $(list_target_partitions); do
        is_rw_candidate_partition "$p" && echo "$p"
    done | busybox awk '!seen[$0]++'
}

rw_minimize() {
    local fs
    fs="$(img_fs_marker "$1")"
    echo "Minimize $1 fs=$fs" &>>$LOG
    case "$fs" in
    f2fs)
        # F2FS tools only safely expand prebuilt filesystems; do not shrink here.
        load_f2fs_tools
        echo "Skip F2FS shrink for $1" &>>$LOG
        ;;
    *)
        resize2fs -f "$1" $(calc "$(stat -c%s "$1")*1.25/512")s &>>$LOG
        e2fsck -y -E unshare_blocks "$1" &>>$LOG
        resize2fs -f -M "$1" &>>$LOG
        resize2fs -f -M "$1" &>>$LOG
        ;;
    esac
}

rw_expand() {
    local fs
    fs="$(img_fs_marker "$1")"
    case "$fs" in
    f2fs)
        resize_f2fs_image "$1" "$2" ;;
    *)
        echo "Resizing $1 + $2 Bytes to "$(calc "($(stat -c%s "$1")+$2)")" Bytes" &>>$LOG
        resize2fs -f "$1" "$(calc "($(stat -c%s "$1")+$2)/512")"s &>>$LOG ;;
    esac
}

for_rw_imgs() {
    for _img in "$TMP_IMGS"/*.img; do
        [ -f "$_img" ] || continue
        _part="$(basename "$_img" | sed 's|.img$||')"
        is_rw_candidate_partition "$_part" && echo "$_img"
    done
}

