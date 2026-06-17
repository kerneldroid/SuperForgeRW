#!/bin/bash

run_backup_vbmeta() {
    for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT /dev/block/by-name/*vbmeta*; do
        [ -e "$file_vbmeta" ] || continue
        cat "$file_vbmeta" >"$OUT_SUPER_DIR/$(basename "$file_vbmeta").original.img"
    done
}

run_backup_boot_chain() {
    local p cand
    for p in boot init_boot vendor_boot dtbo vendor_dlkm odm_dlkm system_dlkm; do
        for cand in "/dev/block/by-name/${p}${SLOT}" "/dev/block/by-name/${p}"; do
            [ -e "$cand" ] || continue
            cat "$cand" >"$OUT_SUPER_DIR/$(basename "$cand").original.img"
        done
    done
}

run_backup_critical() {
    run_backup_vbmeta
    run_backup_boot_chain
}

snapshot_abort_backup() {
    local mode out ok
    mode="${SNAPSHOT_ABORT_BACKUP_MODE:-sparse}"
    mkdir -p "$OUT_SUPER_DIR" 2>/dev/null
    my_print "Snapshot guard: creating read-only rollback backup before abort"
    if ! check_free_data; then
        my_print "Snapshot guard: not enough free /data space for full super backup; writing diagnostics only"
        run_lpdump "$SUPER_PATH" >"$OUT_SUPER_DIR/lpdump-active-${SLOT:-noslot}-snapshot-abort.txt" 2>/dev/null || true
        getprop >"$OUT_SUPER_DIR/getprop-before-snapshot-abort.txt" 2>/dev/null || true
        return 1
    fi
    case "$mode" in
    row|raw|recovery)
        out="$OUT_SUPER_DIR/super-backup-row-recovery$([ -z "$SLOT" ] || echo "-active-$SLOT")-snapshotstate.img"
        if cat "$SUPER_PATH" >"$out"; then ok=1; else ok=0; fi
        ;;
    sparse|fastboot|*)
        out="$OUT_SUPER_DIR/super-backup-sparse-fastboot$([ -z "$SLOT" ] || echo "-active-$SLOT")-snapshotstate.img"
        if img2simg "$SUPER_PATH" "$out"; then ok=1; else ok=0; fi
        ;;
    esac
    if [ "$ok" = "1" ]; then
        my_print "Snapshot-state super backup saved: $out"
    else
        my_print "Snapshot guard backup failed; no write to super was attempted"
    fi
    run_backup_critical
    run_lpdump "$SUPER_PATH" >"$OUT_SUPER_DIR/lpdump-active-${SLOT:-noslot}-snapshot-abort.txt" 2>/dev/null || true
    getprop >"$OUT_SUPER_DIR/getprop-before-snapshot-abort.txt" 2>/dev/null || true
    cat >"$OUT_SUPER_DIR/README_SNAPSHOTSTATE_BACKUP.txt" <<'EOF'
This backup was created while Virtual A/B COW/snapshot artifacts were active.
It is read-only captured before SuperForgeRW attempted any RW conversion or direct super write.
Prefer letting OTA merge finish and using a clean stock/full-super rollback image when possible.
Do not treat this as a clean post-merge stock super backup.
EOF
}

rm_old_backup() {
    my_print "Please Wait, backing up super..."
    [ -d $OUT_SUPER_DIR ] && {
        rm -f $OUT_SUPER_DIR/super.backup.*img
    } || {
        mkdir $OUT_SUPER_DIR

    }
}

run_backup_sparse() {
    rm_old_backup
    img2simg "$SUPER_PATH" $OUT_SUPER_DIR/super-backup-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img
    my_print "Output file"
    my_print "$OUT_SUPER_DIR/super-backup-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
}

run_backup_row() {
    rm_old_backup
    cat "$SUPER_PATH" >$OUT_SUPER_DIR/super-backup-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img
    my_print "Output file"
    my_print "$OUT_SUPER_DIR/super-backup-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
}

bak_super_to() {

    $FORCE_START && {
        (check_free_data) || abortF 14 9123
        case $BACKUP_ORIGINAL_SUPER in
        "true:row" | "true:recovery")
            run_backup_row
            run_backup_critical
            ;;
        "true:sparse" | "true:fastboot")
            run_backup_sparse
            run_backup_critical
            ;;
        esac

    } || {
        MYSELECT "You want to make a backup of original super?" "YES" "NO"
        case $? in
        1)
            $terminal_on && {
                while ! (check_free_data); do
                    my_print "Still need $(calc "($Ss/1024/1024/1024)+1") GB+ internal storage memory for continue"
                    ui_print "- Enter any key to continue:\n"
                    read ooooo
                done
            } || {
                ! (check_free_data) && {
                    MYSELECT "There is not enough memory in the internal storage. Continue without backup, or abort the operation?" "Continue" "Break"
                    case $? in
                    1) return 1 ;;
                    2) abortF 1 464 ;;
                    esac
                }
            }

            MYSELECT "Output Bak-super.img file for fastboot/sparse or recovery/row?" "FASTBOOT/SPARSE" "RECOVERY/ROW"
            case $? in
            1)
                run_backup_sparse
                ;;
            2)
                run_backup_row
                ;;

            esac
            run_backup_critical
            ;;
        esac
    }
}

