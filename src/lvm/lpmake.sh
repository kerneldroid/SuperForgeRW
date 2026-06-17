#!/bin/bash

build_lpmake_group_args() {
    used_groups=""
    args=""
    fallback_group="$(first_lpdump_group)"
    [ -z "$fallback_group" ] && fallback_group="qti_dynamic_partitions$SLOT"
    for img in "$TMP_IMGS"/*.img; do
        [ -f "$img" ] || continue
        part="$(basename "$img" | sed 's|.img$||')"
        group="$(partition_group_for "$part")"
        [ -z "$group" ] && group="$fallback_group"
        case " $used_groups " in
        *" $group "*) continue ;;
        esac
        used_groups="$used_groups $group"
        # lpmake implicitly has a legacy/default group. Passing
        # "--group default:0" on devices whose lpdump reports the default
        # group causes: "Group already exists: default". Keep partitions
        # assigned to default, but do not emit a duplicate --group arg.
        if [ "$group" = "default" ]; then
            echo "lpmake group: $group is implicit; skip duplicate --group" &>>$LOG
            continue
        fi
        gsize="$(group_max_for "$group")"
        [ -z "$gsize" ] && gsize="$(calc "$Ss-6008608")"
        args="$args --group $group:$gsize"
        echo "lpmake group: $group size $gsize" &>>$LOG
    done
    echo "$args"
}

build_lpmake_partition_args() {
    fallback_group="$(first_lpdump_group)"
    [ -z "$fallback_group" ] && fallback_group="qti_dynamic_partitions$SLOT"
    args=""
    for img in "$TMP_IMGS"/*.img; do
        [ -f "$img" ] || continue
        part="$(basename "$img" | sed 's|.img$||')"
        group="$(partition_group_for "$part")"
        [ -z "$group" ] && group="$fallback_group"
        args="$args --partition $part:none:$(stat -c%s "$img"):$group --image $part=$img"
        echo "lpmake partition: $part group $group size $(stat -c%s "$img")" &>>$LOG
    done
    echo "$args"
}

validate_lpmake_group_limits() {
    local group part img size max sum failed fallback_group
    is_true "$CHECK_GROUP_LIMITS" || return 0
    failed=0
    fallback_group="$(first_lpdump_group)"
    [ -z "$fallback_group" ] && fallback_group="qti_dynamic_partitions$SLOT"
    for group in $(for img in "$TMP_IMGS"/*.img; do
        [ -f "$img" ] || continue
        part="$(basename "$img" | sed 's|.img$||')"
        group="$(partition_group_for "$part")"
        [ -z "$group" ] && group="$fallback_group"
        echo "$group"
    done | busybox awk '!seen[$0]++'); do
        [ -z "$group" ] && continue
        sum=0
        for img in "$TMP_IMGS"/*.img; do
            [ -f "$img" ] || continue
            part="$(basename "$img" | sed 's|.img$||')"
            img_group="$(partition_group_for "$part")"
            [ -z "$img_group" ] && img_group="$fallback_group"
            [ "$img_group" = "$group" ] || continue
            size=$(stat -c%s "$img")
            sum=$(calc "$sum+$size")
        done
        max="$(group_max_for "$group")"
        [ -z "$max" ] && max="$(calc "$Ss-6008608")"
        echo "Group usage check: $group sum=$sum max=$max" &>>$LOG
        # lpdump can report the legacy/default group with Maximum size: 0 while
        # still containing tiny OEM partitions. In liblp/lpmake this is not a
        # usable hard cap for our preflight math. Treat 0 as "unbounded/metadata
        # default" and let lpmake validate the original group semantics.
        if [ "$max" = "0" ]; then
            echo "Group usage check: $group has max=0; skipping hard limit check" &>>$LOG
            continue
        fi
        if [ -n "$max" ] && (calc_int "$sum>$max"); then
            my_print "Group $group too large after rebuild: $sum > $max"
            failed=1
        fi
    done
    [ "$failed" = "0" ] || abortF 67 4303
}

