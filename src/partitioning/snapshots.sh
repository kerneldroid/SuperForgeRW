#!/bin/bash

is_snapshot_partition() {
    case "$1" in
    scratch | scratch_* | *_scratch | *-cow | *_cow | cow_* | *snapshot* | *_snapshot | *-snapshot | *tmp-cow* | *-cow-img*) return 0 ;;
    *) return 1 ;;
    esac
}

snapshot_update_state() {
    [ -f "$LPDUMP" ] || return 1
    busybox awk -F': ' '/^Update state:/ { print $2; exit }' "$LPDUMP" | tr '[:upper:]' '[:lower:]'
}

snapshot_using_snapuserd() {
    [ -f "$LPDUMP" ] || return 1
    busybox awk -F': ' '/^Using snapuserd:/ { print $2; exit }' "$LPDUMP"
}

list_lpdump_cow_partitions() {
    [ -f "$LPDUMP" ] || return 0
    list_lpdump_partition_names 2>/dev/null | grep -E '(^|[_-])(cow|snapshot)($|[_-])|cow|snapshot' || true
}

metadata_snapshot_payloads_exist() {
    # Directory existence alone is not active snapshot state on OPlus A16; empty
    # /metadata/ota/snapshots is common. Treat only real contents/state markers as active.
    [ -d /metadata/ota/snapshots ] || return 1
    find /metadata/ota/snapshots -mindepth 1 -maxdepth 4 2>/dev/null | grep -E 'cow|snapshot|snapuserd|merge|[.]img|[.]cow|status|state' >/dev/null && return 0
    return 1
}

stale_cow_detected() {
    # lpdump may keep a "cow" group with *-cow partitions even when update_engine
    # reports Update state: none and snapuserd is not used. These stale leftovers
    # should be dropped from staged rebuilds, not treated as active OTA merge.
    [ -f "$LPDUMP" ] || return 1
    list_lpdump_cow_partitions | grep -q . || return 1
    [ "$(snapshot_update_state)" = "none" ] || return 1
    [ "$(snapshot_using_snapuserd)" = "0" ] || return 1
    metadata_snapshot_payloads_exist && return 1
    pidof snapuserd >/dev/null 2>&1 && return 1
    pgrep snapuserd >/dev/null 2>&1 && return 1
    return 0
}

active_snapshot_detected() {
    # Active Virtual A/B state is determined by update_engine/snapuserd/metadata,
    # not by the mere presence of stale *-cow partitions in lpdump metadata.
    local st su
    st="$(snapshot_update_state)"
    su="$(snapshot_using_snapuserd)"
    case "$st" in
    merging|snapshotted|initiated|created|cancelled|unknown|*)
        [ -n "$st" ] && [ "$st" != "none" ] && return 0
        ;;
    esac
    [ "$su" = "1" ] && return 0
    metadata_snapshot_payloads_exist && return 0
    [ -d /data/misc/update_engine_log ] && grep -R -i -m1 'snapshot\|cow\|merge' /data/misc/update_engine_log 2>/dev/null | grep -qi 'merge' && return 0
    pidof snapuserd >/dev/null 2>&1 && return 0
    pgrep snapuserd >/dev/null 2>&1 && return 0
    return 1
}

list_active_snapshot_artifacts() {
    {
        echo "snapshot_update_state=$(snapshot_update_state 2>/dev/null)"
        echo "using_snapuserd=$(snapshot_using_snapuserd 2>/dev/null)"
        pidof snapuserd 2>/dev/null | sed 's/^/snapuserd_pid=/' || true
        pgrep snapuserd 2>/dev/null | sed 's/^/snapuserd_pgrep=/' || true
        if metadata_snapshot_payloads_exist; then
            find /metadata/ota/snapshots -mindepth 1 -maxdepth 4 2>/dev/null || true
        fi
        if stale_cow_detected; then
            echo "stale_lpdump_cow_only=true"
            list_lpdump_cow_partitions | sed 's/^/stale: /'
        else
            list_lpdump_cow_partitions | sed 's/^/cow_or_snapshot_partition: /'
        fi
    } | busybox awk 'NF && !seen[$0]++'
}

write_snapshot_guard_report() {
    local report target_sdk target_release recovery_sdk target_brand target_model
    [ -n "$OUT_SUPER_DIR" ] || OUT_SUPER_DIR=/data/media/0/RO2RW_SUPER
    mkdir -p "$OUT_SUPER_DIR" "$NEO_LOGS" 2>/dev/null
    report="$OUT_SUPER_DIR/SNAPSHOT_GUARD_REPORT.txt"
    target_sdk="${ANDROID_SDK:-$(getprop ro.build.version.sdk 2>/dev/null)}"
    target_release="${ANDROID_RELEASE:-$(getprop ro.build.version.release 2>/dev/null)}"
    recovery_sdk="$(getprop orangefox.rom.sdk 2>/dev/null)"
    target_brand="$(getprop ro.product.brand 2>/dev/null)"
    target_model="$(getprop ro.product.model 2>/dev/null)"
    {
        echo "SuperForgeRW Nexus snapshot guard report"
        echo "version=$VER"
        echo "date=$(date 2>/dev/null)"
        echo "target_android_release=${target_release:-unknown}"
        echo "target_android_sdk=${target_sdk:-unknown}"
        echo "recovery_sdk=${recovery_sdk:-unknown}"
        echo "brand=${target_brand:-unknown}"
        echo "model=${target_model:-unknown}"
        echo "slot=${SLOT:-unknown}"
        echo "virtual_ab=$(getprop ro.virtual_ab.enabled 2>/dev/null)"
        echo "super=${SUPER_PATH:-unknown}"
        echo ""
        if active_snapshot_detected; then
            echo "Reason: active Virtual A/B snapshot/merge state was detected."
            echo "Action: boot Android normally and let OTA/snapshot merge finish, then rerun."
            echo "Do not flash a rebuilt super image while active snapshot state exists."
        elif stale_cow_detected; then
            echo "Reason: stale/inactive lpdump COW partitions were detected."
            echo "Action: staged build may proceed; stale COW partitions are dropped from rebuilt super when DROP_STALE_COW_PARTITIONS=true."
            echo "Do not direct-flash on locked bootloader. Use generated image only with a valid rollback plan."
        else
            echo "Reason: no active snapshot state detected."
            echo "Action: normal staged build rules apply."
        fi
        echo ""
        echo "Snapshot/COW artifacts:"
        list_active_snapshot_artifacts | sed 's/^/  /'
        echo ""
        if [ -f "$LPDUMP" ]; then
            echo "lpdump COW/snapshot partitions:"
            list_lpdump_partition_names | grep -E 'cow|snapshot' | sed 's/^/  /' || true
            echo ""
            echo "active-slot target partitions excluding COW/snapshot:"
            list_target_partitions | sed 's/^/  /' || true
            echo ""
            echo "RW candidates after allow/deny rules:"
            list_rw_candidate_partitions | sed 's/^/  /' || true
            echo ""
            echo "OPlus reclaim-mode candidates:"
            list_reclaim_partition_candidates | sed 's/^/  /' || true
        fi
    } >"$report" 2>/dev/null
    echo "Snapshot guard report: $report" &>>$LOG
}

