#!/bin/bash

make_super() {

    local mslot Ss group_s part_s lp
    if [ "$(getenforce)" = "Enforcing" ]; then
        setenforce 0
        trap 'setenforce 1' RETURN
    fi

    mslot=$(parse_lpdump_metadata_slots)
    Ss=$(parse_lpdump_super_size)
    [ -z "$Ss" ] && abortF 58 5161
    group_s=$(build_lpmake_group_args)
    part_s=$(build_lpmake_partition_args)
    [ -z "$group_s" ] && abortF 58 5162
    [ -z "$part_s" ] && abortF 58 5163
    bak_super_to
    if $terminal_on; then
        while ! (check_free_data) && $terminal_on; do
            remove_list "Continue"
        done
        MYSELECT "Make super image for"             "Fastboot/Bootloader"             "Recovery"
        case $? in
        1)
            my_print "Making new super and saving to"
            my_print "$OUT_SUPER_DIR/super.rw.sparse.fastboot.img"
            lp="--metadata-size ${LP_METADATA_SIZE:-65536} --sparse --super-name super --metadata-slots $mslot --device super:$Ss $group_s $part_s --output $OUT_SUPER_DIR/super-rw-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
            SUPER_WRITE_MODE=staged
            ;;
        2)
            my_print "Making new super and saving to"
            my_print "$OUT_SUPER_DIR/super.rw.row.recovery.img"
            lp="--metadata-size ${LP_METADATA_SIZE:-65536} --super-name super --metadata-slots $mslot --device super:$Ss $group_s $part_s --output $OUT_SUPER_DIR/super-rw-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
            SUPER_WRITE_MODE=staged
            ;;
        esac

    else
        [ -d "$OUT_SUPER_DIR/" ] || mkdir -p "$OUT_SUPER_DIR"
        if [ "${ALLOW_DIRECT_SUPER_FLASH:-false}" = "true" ]; then
            my_print "Making new super and writing directly to block $SUPER_PATH"
            SUPER_WRITE_MODE=direct
            lp="--metadata-size ${LP_METADATA_SIZE:-65536} --super-name super --metadata-slots $mslot --device super:$Ss $group_s $part_s --output "$SUPER_PATH""
        else
            my_print "Making staged RW super image only; direct block write is disabled"
            SUPER_WRITE_MODE=staged
            case "$AUTO_STAGED_OUTPUT" in
            sparse|fastboot)
                my_print "Output: $OUT_SUPER_DIR/super-rw-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
                lp="--metadata-size ${LP_METADATA_SIZE:-65536} --sparse --super-name super --metadata-slots $mslot --device super:$Ss $group_s $part_s --output $OUT_SUPER_DIR/super-rw-sparse-fastboot$([ -z $SLOT ] || echo "-active-$SLOT").img"
                ;;
            row|raw|recovery|*)
                my_print "Output: $OUT_SUPER_DIR/super-rw-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
                lp="--metadata-size ${LP_METADATA_SIZE:-65536} --super-name super --metadata-slots $mslot --device super:$Ss $group_s $part_s --output $OUT_SUPER_DIR/super-rw-row-recovery$([ -z $SLOT ] || echo "-active-$SLOT").img"
                ;;
            esac
        fi
    fi
    echo $lp &>>$LOG
    validate_lpmake_group_limits

    lpmake $lp &>>$LOG || {
        my_print "lpmake failed. Check $LOG and $LPDUMP; no direct block write was performed unless ALLOW_DIRECT_SUPER_FLASH=true."
        abortF 66 949
    }

}

calc_super() {

    local filei Ss sort_size all_size_img free_size others_num_img others_img start_calc_super i
    my_print "calculating free size and expanding imgs"
    for i in $(for_rw_imgs); do rw_minimize "$i"; done
    Ss=$(for i in $(run_lpdump "$SUPER_PATH" | grep -F "Size:" | busybox awk '{print $2}'); do (calc_int "$i>20") && echo $i && break; done)
    for filei in $(for_rw_imgs); do
        force_umount "${filei%.img*}" || abortF 3 274
        if [ "$(img_fs_marker "$filei")" = "f2fs" ]; then
            echo "Skip temporary +2GB expand for F2FS $filei because F2FS shrink is not supported safely" &>>$LOG
        else
            rw_expand "$filei" 2147483648
        fi
    done
    $terminal_on && {
        my_print "The script is paused. You can manually modify RW candidate .img files in $TMP_IMGS only. Preserve-only images should not be mounted/edited."
        write_mount_sh(){
        rm -f $TMP_IMGS/auto_mount_parts.sh
        echo "for file in $(for_rw_imgs) ; do" >> $TMP_IMGS/auto_mount_parts.sh
        echo "    "'umount -fl ${file%\.img*} &>>/dev/null' >> $TMP_IMGS/auto_mount_parts.sh
        echo "    "'umount -fl ${file%\.img*} &>>/dev/null' >> $TMP_IMGS/auto_mount_parts.sh
        echo "    "'mount -w $file ${file%\.img*} &>>/dev/null || mount -w $file ${file%\.img*} &>>/dev/null || mount -w $file ${file%\.img*} &>>/dev/null' >> $TMP_IMGS/auto_mount_parts.sh
        echo "    "'mountpoint -q ${file%\.img*} && echo "Mounted ./$(basename $file) to ${file%\.img*}" || echo "Problem with mounting $(basename $file)"' >> $TMP_IMGS/auto_mount_parts.sh
        echo "done" >> $TMP_IMGS/auto_mount_parts.sh
        }
        write_mount_sh
        echo -n "- Enter any key to continue:"
        read tick_sedhshdgg
    }
    for filei in $(for_rw_imgs); do
        force_umount "${filei%.img*}"
        rw_minimize "$filei"
        case $RW_SIZE_MOD in
        FIXED)
            rw_expand "$filei" "$(calc "$RW_SIZE*1024*1024")"
            ;;
        esac
        mount_rw_image "$filei" "${filei%.img*}" || abortF 3 295
    done

    sort_size=6
    if $FORCE_START; then
        if (calc_int "$(calc_imgs)>$(calc "$Ss-8388608$($f2fs_re && echo "-262144000")")"); then
            if is_true "$AUTO_INSTALL_MODE" && is_true "$AUTO_PROMPT_APP_REMOVAL" && is_true "$AUTO_CRITICAL_PROMPTS"; then
                my_print "AutoSafe: not enough space for rebuilt super; user choice required before removing apps from images"
                while (calc_int "$(calc_imgs)>$(calc "$Ss-8388608$($f2fs_re && echo "-262144000")")"); do
                    remove_list "Break" || break
                done
                (calc_int "$(calc_imgs)>$(calc "$Ss-8388608$($f2fs_re && echo "-262144000")")") && {
                    my_print "AutoSafe: still not enough space after user app-removal step; aborting without writing super"
                    abortF 91 420
                }
            else
                abortF 91 420
            fi
        fi

    else
        while (calc_int "$(calc_imgs)>$(calc "$Ss-8388608$($f2fs_re && echo "-262144000")")"); do
            remove_list
        done
        MYSELECT "You can remove something, you want?" "Yes" "No"
        case $? in
        1)
            while true; do
                remove_list Break || break
            done
            ;;
        esac
    fi
    for filei in $(for_rw_imgs); do
        force_umount "${filei%.img*}"
        rw_minimize "$filei"
    done

    all_size_img=$(calc_imgs)
    case $RW_SIZE_MOD in
    MAX)
        free_size=$(calc "$Ss-$all_size_img$($f2fs_re && echo "-262144000")")

        others_num_img=0
        start_calc_super=false
        others_img=""
        if (calc_int "16777216<$free_size"); then
            start_calc_super=true
            free_size=$(calc "$free_size-16777216")
        elif (calc_int "8388608<$free_size"); then
            start_calc_super=true
            free_size=$(calc "$free_size-8388608")
        fi

        for i in $(for_rw_imgs); do
            case $(basename "$i") in
            system_ext_a.img | system_ext_b.img | system_ext.img)
                RW_SIZE_SE=$(calc "$free_size/100*$RW_SIZE_SE")
                rw_expand "$i" "$RW_SIZE_SE"
                ;;
            system_a.img | system_b.img | system.img)
                RW_SIZE_S=$(calc "$free_size/100*$RW_SIZE_S")
                rw_expand "$i" "$RW_SIZE_S"
                ;;
            vendor_a.img | vendor_b.img | vendor.img)
                RW_SIZE_V=$(calc "$free_size/100*$RW_SIZE_V")
                rw_expand "$i" "$RW_SIZE_V"
                ;;
            product_a.img | product_b.img | product.img)
                RW_SIZE_P=$(calc "$free_size/100*$RW_SIZE_P")
                rw_expand "$i" "$RW_SIZE_P"
                ;;
            *.img)
                others_img="$others_img $i"
                others_num_img=$(calc "$others_num_img+1")
                ;;
            esac
        done
        if (calc_int "$others_num_img>0"); then
            RW_SIZE_OT=$(calc "$free_size/100*$RW_SIZE_OT/$others_num_img")
            for i in $others_img; do
                rw_expand "$i" "$RW_SIZE_OT"
            done
        fi

        ;;
    FIXED)
        calc_int "$(calc "$Ss-$all_size_img-$all_size_for_expand$($f2fs_re && echo "-262144000")")<0" && abortF 91 443
        for i in $(for_rw_imgs); do
            rw_expand "$i" "$(calc "$RW_SIZE*1024*1024")"
        done
        ;;
    esac
}

preflight_dynamic_super() {
    local sdk_now vbstate parts rwparts reclaimparts part_count rw_count reclaim_count recovery_sdk guard_sdk bl_locked
    sdk_now="${ANDROID_SDK:-$(getprop ro.build.version.sdk 2>/dev/null)}"
    vbstate="$(getprop ro.boot.verifiedbootstate 2>/dev/null)"
    recovery_sdk="${RECOVERY_SDK:-$(getprop orangefox.rom.sdk 2>/dev/null)}"
    guard_sdk="${EFFECTIVE_ANDROID_SDK:-$(max_sdk_value "$sdk_now" "$recovery_sdk")}"
    bootloader_flash_locked && bl_locked=true || bl_locked=false
    my_print "Preflight: target SDK=${sdk_now:-unknown}, recovery SDK=${recovery_sdk:-unknown}, guard SDK=${guard_sdk:-unknown}, vbstate=${vbstate:-unknown}, bootloader_locked=${bl_locked}"
    if is_true "$LOCKED_BOOTLOADER_FLASH_GUARD" && is_true "$bl_locked" && [ "${ALLOW_DIRECT_SUPER_FLASH:-false}" = "true" ] && ! is_true "$ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH"; then
        my_print "Direct super flashing requested, but blocked because bootloader/vbmeta state is locked/green"
        ALLOW_DIRECT_SUPER_FLASH=false
    fi
    if is_uint "$recovery_sdk" && is_uint "$sdk_now" && [ "$recovery_sdk" -ge 36 ] && [ "$sdk_now" -lt 36 ]; then
        my_print "Recovery reports SDK $recovery_sdk while mounted target reports SDK $sdk_now; safety guards will use max SDK=$guard_sdk"
    fi
    if is_uint "$guard_sdk" && [ "$guard_sdk" -ge 36 ]; then
        my_print "Android 16/17 guard profile active"
        if [ "${ALLOW_DIRECT_SUPER_FLASH:-false}" = "true" ] && [ "${ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH:-false}" != "true" ]; then
            my_print "Direct super flashing requested, but blocked on Android 16/17 unless ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH=true"
            ALLOW_DIRECT_SUPER_FLASH=false
        fi
    fi
    if active_snapshot_detected; then
        if is_true "$OPLUS_RECLAIM_MODE" && ! is_true "$ALLOW_RECLAIM_WITH_SNAPSHOT"; then
            my_print "OPlus reclaim mode requested, but active snapshot/merge state exists; refusing to delete/rebuild OEM payloads"
        fi
        if is_true "$ABORT_ON_ACTIVE_SNAPSHOT"; then
            if is_true "$BACKUP_BEFORE_SNAPSHOT_ABORT"; then
                snapshot_abort_backup
            fi
            write_snapshot_guard_report
            my_print "Active Virtual A/B snapshot/merge state detected; build is blocked before any super write"
            my_print "Snapshot guard report: $OUT_SUPER_DIR/SNAPSHOT_GUARD_REPORT.txt"
            my_print "Boot Android normally, let OTA/snapshot merge finish, then rerun"
            if is_true "$SNAPSHOT_REPORT_ONLY"; then
                my_print "SNAPSHOT_REPORT_ONLY=true: stopping after diagnostic report without treating this as a flash failure"
                abortS
            fi
            abortF 93 16018
        fi
    elif stale_cow_detected; then
        write_snapshot_guard_report
        my_print "Inactive/stale lpdump COW partitions detected, but snapshot state is none and snapuserd is off"
        if is_true "$DROP_STALE_COW_PARTITIONS"; then
            my_print "Stale COW partitions will be excluded from staged rebuild"
        else
            my_print "DROP_STALE_COW_PARTITIONS=false is unsafe; COW partitions are still ignored by partition filters"
        fi
        if is_true "$OPLUS_RECLAIM_MODE"; then
            my_print "OPlus reclaim mode may proceed because this is stale COW, not active OTA merge"
        fi
        if ! is_true "$ALLOW_STAGED_BUILD_WITH_STALE_COW"; then
            my_print "ALLOW_STAGED_BUILD_WITH_STALE_COW=false: stopping after report"
            abortF 93 16019
        fi
    fi
    parts="$(list_target_partitions | tr '\012' ' ')"
    rwparts="$(list_rw_candidate_partitions | tr '\012' ' ')"
    reclaimparts="$(list_reclaim_partition_candidates | tr '\012' ' ')"
    part_count="$(echo "$parts" | busybox awk '{print NF}')"
    rw_count="$(echo "$rwparts" | busybox awk '{print NF}')"
    reclaim_count="$(echo "$reclaimparts" | busybox awk '{print NF}')"
    my_print "Preflight partitions: ${part_count:-0} dynamic partitions; ${rw_count:-0} RW candidates"
    echo "Preflight target partitions: $parts" &>>$LOG
    echo "Preflight RW candidates: $rwparts" &>>$LOG
    echo "Preflight OPlus reclaim candidates: $reclaimparts" &>>$LOG
    if is_true "$OPLUS_RECLAIM_MODE"; then
        my_print "OPlus reclaim mode is ON: ${reclaim_count:-0} OEM dynamic partitions will be excluded from rebuilt super"
        my_print "Reclaim candidates: ${reclaimparts:-none}"
    fi
    [ "${part_count:-0}" = "0" ] && abortF 57 7601
    [ "${rw_count:-0}" = "0" ] && abortF 57 7602
    if is_true "$SAFE_COLOROS_MODE" && is_true "$IS_OPLUS_FAMILY"; then
        my_print "ColorOS/OPlus mode: OEM dynamic partitions are preserved unless allowlisted"
    fi
    if [ "${ALLOW_DIRECT_SUPER_FLASH:-false}" != "true" ]; then
        my_print "Direct super flashing disabled. ZIP will build a staged super image in OUT_SUPER_DIR"
    fi
    for g in $(for p in $parts; do partition_group_for "$p"; done | busybox awk '!seen[$0]++'); do
        [ -z "$g" ] && continue
        echo "Preflight group $g max $(group_max_for "$g")" &>>$LOG
    done
}

