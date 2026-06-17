#!/bin/bash

run_lpdump_cmd() {
    # lpdump versions differ: some accept --slot=0/1, older builds accept suffixes,
    # and A-only devices need no slot arg. Try all safe variants.
    _bin="$1"
    _super="$2"
    [ -z "$_bin" ] && return 1
    [ -z "$_super" ] && return 1
    if [ -n "$SLOT_NUM" ]; then
        "$_bin" --slot="$SLOT_NUM" "$_super" && return 0
    fi
    if [ -n "$SLOT" ]; then
        "$_bin" --slot="$SLOT" "$_super" && return 0
        "$_bin" --slot="${SLOT#_}" "$_super" && return 0
    fi
    "$_bin" "$_super"
}

run_lpdump() {
    run_lpdump_cmd "$lpdump_bin" "$1"
}

list_lpdump_partition_names() {
    busybox awk '
        BEGIN { pt=0 }
        /^Partition table:/ { pt=1; next }
        /^Block device table:/ || /^Group table:/ || /^Super partition layout:/ { pt=0 }
        pt && /^[ \t]*Name:/ { print $2 }
    ' "$LPDUMP"
}

list_target_partitions() {
    for p in $(list_lpdump_partition_names); do
        is_snapshot_partition "$p" && { echo "Skip transient partition: $p" &>>$LOG; continue; }
        part_matches_slot "$p" || { echo "Skip inactive-slot partition: $p" &>>$LOG; continue; }
        is_reclaim_partition "$p" && { echo "Skip reclaim-mode partition: $p" &>>$LOG; continue; }
        echo "$p"
    done | busybox awk '!seen[$0]++'
}

partition_group_for() {
    part_query="$1"
    busybox awk -v part="$part_query" '
        BEGIN { pt=0; hit=0 }
        /^Partition table:/ { pt=1; next }
        /^Block device table:/ || /^Group table:/ || /^Super partition layout:/ { pt=0 }
        pt && /^[ \t]*Name:/ { hit=($2 == part) }
        hit && /^[ \t]*Group:/ { print $2; exit }
    ' "$LPDUMP"
}

first_lpdump_group() {
    busybox awk '
        BEGIN { gt=0 }
        /^Group table:/ { gt=1; next }
        /^Super partition layout:/ || /^Block device table:/ || /^Partition table:/ { if (gt) gt=0 }
        gt && /^[ \t]*Name:/ { print $2; exit }
    ' "$LPDUMP"
}

group_max_for() {
    group_query="$1"
    busybox awk -v grp="$group_query" '
        BEGIN { gt=0; hit=0 }
        /^Group table:/ { gt=1; next }
        /^Super partition layout:/ || /^Block device table:/ || /^Partition table:/ { if (gt) gt=0 }
        gt && /^[ \t]*Name:/ { hit=($2 == grp) }
        hit && /^[ \t]*Maximum size:/ { print $3; exit }
    ' "$LPDUMP"
}

parse_lpdump_super_size() {
    for i in $(grep -F "Size:" "$LPDUMP" | busybox awk '{print $2}'); do
        (calc_int "$i>20") && echo "$i" && return 0
    done
    return 1
}

parse_lpdump_metadata_slots() {
    for i in $(grep -F "Metadata slot count:" "$LPDUMP" | busybox awk '{print $4}'); do
        echo "$i" && return 0
    done
    echo 2
}

