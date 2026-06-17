#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$DIR/../src/ui/logging.sh"
source "$DIR/../src/utils/math.sh"
source "$DIR/../src/utils/strings.sh"
source "$DIR/../src/utils/tools.sh"
source "$DIR/../src/lvm/lpdump.sh"
source "$DIR/../src/lvm/lpmake.sh"
source "$DIR/../src/fs/detect.sh"
source "$DIR/../src/fs/f2fs.sh"
source "$DIR/../src/fs/erofs.sh"
source "$DIR/../src/fs/mount.sh"
source "$DIR/../src/partitioning/snapshots.sh"
source "$DIR/../src/partitioning/rw_logic.sh"
source "$DIR/../src/partitioning/migration.sh"
source "$DIR/../src/backup/backup.sh"
source "$DIR/../src/core/super.sh"
source "$DIR/../src/core/image.sh"
source "$DIR/../src/core/preflight.sh"

arg1="$1"
arg2="$2"
arg3="$3"
VER="EXAMPLE"
RSTATUS="EXAMPLE"
arch="EXAMPLE"
# SuperForgeRW compatibility defaults. These prevent empty variables
# from being executed as shell commands before config.txt is loaded.
FORCE_START=false
AUTO_INSTALL_MODE=false
AUTO_CRITICAL_PROMPTS=true
AUTO_PROMPT_APP_REMOVAL=true
AUTO_STAGED_OUTPUT="sparse"
REMOVE_TIMEOUT_KEY=false
IF_VALUE_WRONG=false
IF_NO_DATA_CONTINUE=false
IF_EXT4_MOUNT_PROBLEM_CONTINUE=false
DFE_PATCH=false
ALLOW_DFE_PATCH=false
BACKUP_ORIGINAL_SUPER=false
WHAT_DO_SCRIPT=""
RW_SIZE="S=70% V=10% P=10% SE=5% OT=5%"
RW_SIZE_MOD="MAX"
SAFE_COLOROS_MODE=true
INCLUDE_UNSLOTTED_PARTITIONS=true
STRICT_LPDUMP_PARTITION_PARSE=true
AUTO_BACKUP_METADATA=true
ALLOW_PARTITIONS="system system_ext product vendor odm"
DENY_PARTITIONS="boot init_boot vendor_boot vbmeta vbmeta_system vbmeta_vendor pvmfw misc metadata userdata cache modem* bluetooth* abl* xbl* aop* tz* hyp* keymaster* qupfw* uefisecapp* devcfg* dsp* *_dlkm *_firmware oplus* my_* reserve* cust*"
PATCH_FBE_FLAGS=true
PATCH_AVB_FLAGS=false
PATCH_STORAGE_FLAGS=false
SCOPED_FSTAB_PATCH=true
DISABLE_LITERW_BY_DEFAULT=true
ALLOW_DIRECT_SUPER_FLASH=false
ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH=false
# v4.3.4: distinguish active OTA snapshots from stale/inactive lpdump COW leftovers.
ABORT_ON_ACTIVE_SNAPSHOT=true
DROP_STALE_COW_PARTITIONS=true
ALLOW_STAGED_BUILD_WITH_STALE_COW=true
LOCKED_BOOTLOADER_FLASH_GUARD=true
ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH=false
CHECK_GROUP_LIMITS=true
PATCH_FSTAB_RW_ONLY=true
SNAPSHOT_REPORT_ONLY=false
# Create a read-only backup and diagnostics before aborting on active Virtual A/B COW/snapshot state.
BACKUP_BEFORE_SNAPSHOT_ABORT=true
SNAPSHOT_ABORT_BACKUP_MODE="sparse"
LP_METADATA_SIZE=65536
TARGET_FS_FROM_EXT4="f2fs"
TARGET_FS_FROM_EROFS="ext4"
TARGET_FS_FROM_F2FS="f2fs"
TARGET_FS_FROM_OTHER="ext4"
REQUIRE_F2FS_TOOLS=true
F2FS_IMAGE_EXTRA_MB=160
F2FS_POPULATE_MODE="auto"
ALLOW_F2FS_MOUNTCOPY_FALLBACK=true
F2FS_IMAGE_SIZE_POLICY="source"
F2FS_FALLBACK_COPY_MODE="auto"
f2fs_re=false
SUPER_WRITE_MODE="unknown"
case $1 in
terminal)
    terminal_on=true
    boot_on=$(getprop sys.boot_completed)
    [ -z "$boot_on" ] && boot_on=$(getprop dev.bootcomplete)
    [ "$boot_on" = 1 ] && boot_on=true
    ;;
*)
    terminal_on=false
    ui_print() {
        echo -e "ui_print $1\nui_print" >>"/proc/self/fd/$arg2"
        [ -z $LOG ] || echo -e "ui_print: $*" &>>$LOG
    }

    boot_on=false
    ;;

esac

find_block() {
    # Unified resolver: mapper first for dynamic partitions, then by-name and fallback scan.
    local BLOCK DEVICE BASE SLOT_SUFFIX CAND
    SLOT_SUFFIX="${SLOT:-$(getprop ro.boot.slot_suffix 2>/dev/null)}"
    for BLOCK in "$@"; do
        [ -z "$BLOCK" ] && continue
        BASE="$BLOCK"
        case "$BASE" in
            *_a|*_b) BASE="${BASE%_*}" ;;
        esac
        for CAND in \
            "/dev/block/mapper/${BLOCK}" \
            "/dev/block/by-name/${BLOCK}" \
            "/dev/block/bootdevice/by-name/${BLOCK}" \
            "/dev/block/mapper/${BASE}${SLOT_SUFFIX}" \
            "/dev/block/by-name/${BASE}${SLOT_SUFFIX}" \
            "/dev/block/bootdevice/by-name/${BASE}${SLOT_SUFFIX}" \
            "/dev/block/mapper/${BASE}" \
            "/dev/block/by-name/${BASE}" \
            "/dev/block/bootdevice/by-name/${BASE}" \
            "/dev/block/$BLOCK"; do
            if [ -e "$CAND" ]; then
                DEVICE="$(readlink -f "$CAND")"
                echo "$DEVICE"
                echo "Finding $BLOCK to $DEVICE" &>>$LOG
                return 0
            fi
        done
        DEVICE=$(find /dev/block/ \( -type b -o -type c -o -type l \) -iname "$BLOCK" 2>/dev/null | head -n 1)
        if [ -n "$DEVICE" ]; then
            DEVICE="$(readlink -f "$DEVICE")"
            echo "$DEVICE"
            echo "Finding $BLOCK to $DEVICE by fallback scan" &>>$LOG
            return 0
        fi
    done
    echo "Can't find:$*" &>>$LOG
    return 1
}


MYSELECT() {
    local text_for_select text_select text_input text_commend main_text tick_for OUT_SELECT all_ticks tick_select text_S
    ui_print ""
    text_for_select=""
    text_select=""
    text_input=""
    text_commend=""
    main_text="$1"
    echo $main_text | grep -q ":EXIT:" && OUT_SELECT="EXIT" && main_text=${main_text%:EXIT:*} || OUT_SELECT="EXIT"
    [ -z "$main_text" ] || my_print "$main_text"
    ui_print ""
    tick_for=1
    for text_S in "$@"; do
        if ! [ "$text_S" = "$1" ]; then
            [ -z "$text_S" ] && break
            text_input=${text_S%:comment:*}
            text_select=${text_input#*:select:}
            text_input=${text_input%:select:*}
            text_commend=${text_S#*:comment:}

            my_print "selected" "${tick_for}) [$text_input]"
            if (echo "$text_S" | grep -q ':comment:'); then
                my_print "commented" "${text_commend}"
            fi
            [ -z "$text_for_select" ] &&
                text_for_select="${tick_for}) $text_select" ||
                text_for_select="${text_for_select}\n${tick_for}) ${text_select}"
            tick_for=$((tick_for + 1))
        fi
    done

    text_for_select="${text_for_select}\n${OUT_SELECT}"
    my_print "selected" "${tick_for}) [$OUT_SELECT]"
    tick_select=1
    all_ticks=$(echo -e $text_for_select | wc -l)
    $boot_on && {
        while true; do
            echo -n " - Select num: "
            read tick_select
            if (calc_int "$tick_for>=$tick_select") && (calc_int "$tick_select>=1"); then
                break
            else
                my_print "Enter a number from 1 to $tick_for"
            fi
        done
    } || {
        my_print "Use Volume Key (+) to switch. Use Volume key (-) to select"
        while true; do
            my_print "selected" "$tick_select)  > $(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||') <"
            if chooseport 60; then
                tick_select=$((tick_select + 1))
            else
                break
            fi
            if [ $tick_select -gt $all_ticks ]; then
                tick_select=1
            fi
        done
    }
    my_print "selected" "$tick_select)  >[$(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||')]<"
    ui_print " "
    ui_print "**==================================***"
    if [ "$(echo -e $text_for_select | head -n$tick_select | tail -n1)" = "${OUT_SELECT}" ]; then
        [ "$OUT_SELECT" = "EXIT" ] && abortF 0 214 || abortF 0 214.1 #main_menu
    fi
    if [ $all_ticks -le 3 ]; then
        [ $tick_select = 1 ] && return 1
        [ $tick_select = 2 ] && return 2
    else
        return $tick_select
    fi
}

chooseport() {
    # Original idea by chainfire and ianmacd @xda-developers
    [ "$1" ] && local delay=$1 || local delay=3
    local error=false
    while true; do
        local count=0
        while true; do
            timeout 0.5 getevent -lqc 1 2>&1 >$TMP_NEO/events &
            sleep 0.1
            count=$((count + 1))
            if (grep -q 'KEY_VOLUMEUP *DOWN' $TMP_NEO/events); then
                return 0
            elif (grep -q 'KEY_VOLUMEDOWN *DOWN' $TMP_NEO/events); then
                return 1
            fi
            [ $count -gt 100 ] && break
        done
        if $error && ! $REMOVE_TIMEOUT_KEY; then
            my_print "TimeOUT key"
            abortF 90 243
        else
            error=true
            ui_print " "
            my_print "TimeOUT"
        fi
    done
}


resolve_partition_block() {
    part_name="$1"
    part_base="$(strip_slot_suffix "$part_name")"
    find_block "$part_name" "$part_base" "${part_base}${SLOT}" "${part_base}_${SLOT#_}"
}
part_matches_slot() {
    p="$1"
    [ -z "$SLOT" ] && return 0
    case "$p" in
    *"$SLOT") return 0 ;;
    *_a | *_b) return 1 ;;
    *) is_true "$INCLUDE_UNSLOTTED_PARTITIONS" && return 0 || return 1 ;;
    esac
}
part_match_list() {
    local p="$1" base pat
    base="$(part_base_name "$p")"
    shift
    for pat in "$@"; do
        [ -z "$pat" ] && continue
        case "$p" in $pat) return 0 ;; esac
        case "$base" in $pat) return 0 ;; esac
    done
    return 1
}











calc_imgs() {
    pop=0
    for i in $TMP_IMGS/*.img; do
        pop=$(calc "$(stat -c%s "$i")+$pop")
        echo "Calculate: "$i", $(stat -c%s "$i"), all now:$pop" &>>$LOG
    done
    echo $pop
    echo "All size imgs:$pop" &>>$LOG
}

tabul="
"
DFE() {

    local fstabp="$1" fstabp_now remove_now g g2 remove i
    if ! is_true "$ALLOW_DFE_PATCH"; then
        my_print "DFE patch is locked by config. Set ALLOW_DFE_PATCH=true only if you accept data-loss risk."
        return 0
    fi
    [ -f "$fstabp" ] && cp -af "$fstabp" "$fstabp.superforgerw.bak" &>>$LOG
    [ "${PATCH_FBE_FLAGS:-true}" = "true" ] || {
        my_print "DFE flag patching disabled by profile"
        return 0
    }

    g=$(

        echo "fileencryption="
        echo "forcefdeorfbe="
        echo "encryptable="
        echo "forceencrypt="
        echo "metadata_encryption="
        echo "keydirectory="
        [ "${PATCH_AVB_FLAGS:-false}" = "true" ] && echo "avb="
        [ "${PATCH_AVB_FLAGS:-false}" = "true" ] && echo "avb_keys="

    )

    g2=$(

        [ "${PATCH_AVB_FLAGS:-false}" = "true" ] && echo "avb"
        [ "${PATCH_STORAGE_FLAGS:-false}" = "true" ] && echo "quota"
        [ "${PATCH_STORAGE_FLAGS:-false}" = "true" ] && echo "inlinecrypt"
        [ "${PATCH_STORAGE_FLAGS:-false}" = "true" ] && echo "wrappedkey"

    )
    my_print "Patching $(basename "$fstabp") for DFE (FBE=$PATCH_FBE_FLAGS AVB=$PATCH_AVB_FLAGS STORAGE=$PATCH_STORAGE_FLAGS)"
    while ($(
        for i in $g; do grep -q "$i" "$fstabp" && return 0; done
        return 1
    )); do
        fstabp_now=$(cat "$fstabp")
        for remove in $g; do
            grep -q "$remove" "$fstabp" && {
                remove_now="${fstabp_now#*"$remove"}"
                remove_now="${remove_now%%,*}"
                remove_now="${remove}${remove_now%%"$tabul"*}"
            } || {
                continue
            }
            grep -q ",$remove_now" "$fstabp" && {
                sed -i 's|,'$remove_now'||' "$fstabp" &>>$LOG
            }
            grep -q "$remove_now" "$fstabp" && {
                sed -i 's|'$remove_now'||' "$fstabp" &>>$LOG
            }
            echo " Remove $remove_now FLAG" &>>$LOG
        done
    done
    if ($(
        for i in $g2; do
            grep -q "$i" "$fstabp" && return 0
        done
        return 1
    )); then
        for remove in $g2; do
            grep -q ",$remove" "$fstabp" && sed -i 's|,'$remove'||g' "$fstabp" &>>$LOG
            grep -q "$remove," "$fstabp" && sed -i 's|'$remove',||g' "$fstabp" &>>$LOG
            grep -q "$remove" "$fstabp" && sed -i 's|'$remove'||g' "$fstabp" &>>$LOG
            echo "Remove $remove FLAG" &>>$LOG
        done
    fi
}

remove_list() {

    local move_list FILE_REM f filei filesss
    clear
    if (calc_int "$sort_size>8"); then
        sort_size=8
    elif (calc_int "$sort_size<1"); then
        sort_size=1
    fi
    #size_plus=$( if (( $size_plus > 200 )) ; then echo 100 ; elif (( $size_plus > 100 )) ; then echo 50 ; elif (( $size_plus > 50 )) ; then echo 20 ; elif (( $size_plus > 10 )) ; then echo 10 ; fi )

    calc_sort $sort_size
    MYSELECT "You need to remove something, Sorting apps list ${sort_min}Mb-${sort_max}Mb$([ "$1" = "Break" ] || echo ", need $(calc "($(calc_imgs)-$Ss-8388608)/1024/1024") mb free size:")" \
        $1 "Sort to $(
            calc_sort $(calc "$sort_size+1")
            echo "${sort_min}Mb-${sort_max}Mb"
        )" \
        "Sort to $(
            calc_sort $(calc "$sort_size-1")
            echo "${sort_min}Mb-${sort_max}Mb"
        )" \
        $(
            calc_sort $sort_size
            for filesss in $(find $TMP_IMGS/* -mindepth 1 -size +${sort_min}M -and -size -${sort_max}M -type f -name "*.apk") \
                $(find $TMP_IMGS/* -mindepth 1 -size +${sort_min}M -and -size -${sort_max}M -type f -name "*.zip"); do
                echo "$(du -sh "$(dirname $filesss)" | awk '{print $1}')-$(basename "$filesss"):comment:located:$(read_main_dir ${filesss#*"$TMP_IMGS"})"
            done
        )
    move_list=$?
    [ "$1" = "Break" ] && { move_list=$((move_list - 1)); }
    case $move_list in
    0) return 1 ;;
    1) sort_size=$(calc "$sort_size+1") ;;
    2) sort_size=$(calc "$sort_size-1") ;;
    *)
        f=$(echo -e $text_for_select | head -n$tick_select | tail -n1 | sed 's|'$tick_select') ||')
        FILE_REM=$(find "$TMP_IMGS"/ -name "*${f#*-}")
        MYSELECT "REMOVE "$(dirname ${FILE_REM#*"$TMP_IMGS/"})"?" "YES" "NO"
        [ $? = 1 ] && rm -rf $(dirname $FILE_REM)
        for filei in $(for_rw_imgs); do
            force_umount "${filei%.img*}"
            rw_minimize "$filei"
            case $RW_SIZE_MOD in
            FIXED)
                rw_expand "$filei" "$(calc "$RW_SIZE*1024*1024")"
                ;;
            esac
            mount_rw_image "$filei" "${filei%.img*}" || abortF 33 48266

        done

        ;;
    esac

}


check_free_data() {
    if (calc_int "$(df /$check_size_main_path/ | wc -l)==2"); then
        free_data=$(df /$check_size_main_path/ | tail -n1 | busybox awk '{print int($4)}')
    elif (calc_int "$(df /$check_size_main_path/ | wc -l)==3"); then
        free_data=$(df /$check_size_main_path/ | tail -n1 | busybox awk '{print int($3)}')
    else
        my_print "Can't calculate free size data"
        abortF 82 458
    fi
    calc_int "$(calc "$free_data/1024/1024")>$(calc "($Ss/1024/1024/1024)+1")" && {
        return 0
    } || {
        return 1
    }
}







# v4.4.x: local mount wrappers. Some recoveries do not provide the
# original helper commands, and umount on a non-mounted block device may
# return non-zero. That must never abort a staged rebuild.













check_size() {

    if (calc_int "$(df $1 | wc -l)==2"); then
        df -h $1 | tail -n1 | busybox awk '{print $4}'
    elif (calc_int "$(df $1 | wc -l)==3"); then
        df -h $1 | tail -n1 | busybox awk '{print $3}'
    else
        my_print "Can't calculate free size data"
        abortF 82 458
    fi

}

mount_for_check() {
    mount -o rw,remount "$1" &>>$TMP_NEO/check.mnt.$2.txt
    grep -q "read-only" $TMP_NEO/check.mnt.$2.txt && {
        [ "$3" = "Check" ] &&
            my_print "$2 have RO  $(check_size $1) free size" ||
            my_print "$2 It was not possible to assign RW, you need to flash the full version of RO2RW"
    } || {
        my_print "$2 have RW and $(check_size $1) free size"
    }
    rm -f $TMP_NEO/check.mnt.$2.txt
}

read_main_dir() {

    full_path="$1"
    while true; do
        full_path="$(dirname "$full_path")"
        [ "$(dirname "$full_path")" = "." ] && break
        [ "$(dirname "$full_path")" = "/" ] && break
    done
    echo "$full_path"

}

set_config_for_expand() {
    . $TMP_NEO/config.sh
    MYSELECT "Choose the size to expand the partitions 'System=S' 'Product=P' 'System_ext=SE' 'Vendor=V' 'Other sections if any = OT'" \
        "Maximum expansion 1:select:Maximum 1:comment:S=50%, V=20%, P=10%, SE=10% OT=10%" \
        "Maximum expansion 2:select:Maximum 2:comment:S=30%, V=20%, P=20%, SE=20% OT=10%" \
        "Maximum expansion 3:select:Maximum 3:comment:S=30%, V=20%, P=10%, SE=10% OT=30%" \
        "Maximum expansion 4:select:Maximum 4:comment:S=30%, V=30%, P=20%, SE=20% OT=0%" \
        "enlarge each partition by 30Mb:select:+30Mb" \
        "enlarge each partition 50Mb:select:+50Mb" \
        "enlarge each partition 70Mb:select:+70Mb" \
        "enlarge each partition 100Mb:select:+100Mb" \
        "enlarge each partition 150Mb:select:+150Mb" \
        "enlarge each partition 200Mb:select:+200Mb" \
        "enlarge each partition 250Mb:select:+250Mb" \
        "Reading config.txt:select:CUSTOM:comment: Parameters $RW_SIZE_MOD $RW_SIZE" "$($terminal_on && echo "Set your own configuration now")"
    case $? in
    1)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=50% V=20% P=10% SE=10% OT=7%"
        ;;
    2)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=20% P=20% SE=20% OT=7%"
        ;;
    3)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=20% P=10% SE=10% OT=20%"
        ;;
    4)
        RW_SIZE_MOD="MAX"
        RW_SIZE="S=30% V=30% P=20% SE=20% OT=0%"
        ;;
    5)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="30"
        ;;
    6)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="50"
        ;;
    7)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="70"
        ;;
    8)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="100"
        ;;
    9)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="150"
        ;;
    10)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="200"
        ;;
    11)
        RW_SIZE_MOD="FIXED"
        RW_SIZE="250"
        ;;
    13)
        MYSELECT "Distribute space by percentage, or a fixed size?" \
            "Percentage size" "Fixed size"
        case $? in
        1)
            my_print "Value hint: 'System=S' 'Product=P' 'System_ext=SE' 'Vendor=V' 'Other sections if any = OT'"
            free_procent=100
            RW_SIZE=""
            for part_short_name in S V P SE OT; do
                procent_size=101
                while true; do
                    ui_print " "
                    my_print "Available: ${free_procent}%"
                    my_print "Enter the percentage for the partition"
                    echo -n "- Enter % for ${part_short_name}="
                    read procent_size_read
                    procent_size=$procent_size_read
                    if $(calc_int "$procent_size<=$free_procent") && $(calc_int "$procent_size>=0"); then
                        free_procent=$(calc "$free_procent-$procent_size")
                        RW_SIZE="$RW_SIZE ${part_short_name}=${procent_size}%"
                        break
                    else
                        my_print "Enter a value from 0 to $free_procent"
                    fi
                done
            done
            RW_SIZE_MOD="MAX"
            ;;
        2)
            my_print "Enter the size of the increase in megabytes"
            echo -n "- Enter size MB:"
            read RW_SIZE
            RW_SIZE="$RW_SIZE"
            RW_SIZE_MOD="FIXED"
            ;;
        esac

        ;;
    esac
}
my_return() {
    return $1
}
check_rw_func() {
    for part in $(check_rw_partition_lpdump); do

        i=$(resolve_partition_block "$part")

        case $part in
        *-cow*) echo "$part COW" &>>$LOG ;;
        *)
            $terminal_on && {
                mount_for_check "$i" "$part" "Check"
            } || {
                mount -r $i &>>$LOG && {
                    mount_for_check "$i" "$part" "Check"
                } || {
                    my_print "Can't mount $part. This partition is not listed in the fstab file, no mount point available"
                }
            }
            ;;
        esac

    done
}
chek_value() {
    case "$IF_EXT4_MOUNT_PROBLEM_CONTINUE" in
    true | false | 1 | 0)
        echo "IF_EXT4_MOUNT_PROBLEM_CONTINUE finde and have $IF_EXT4_MOUNT_PROBLEM_CONTINUE" &>>$LOG
        ;;
    *)
        my_print "IF_EXT4_MOUNT_PROBLEM_CONTINUE Has an incorrect value"
        return 1
        ;;
    esac
    case "$IF_NO_DATA_CONTINUE" in
    true | false | 1 | 0)
        echo "IF_NO_DATA_CONTINUE finde and have $IF_NO_DATA_CONTINUE" &>>$LOG
        ;;
    *)
        my_print "IF_NO_DATA_CONTINUE Has an incorrect value"
        return 1
        ;;
    esac
    case "$BACKUP_ORIGINAL_SUPER" in
    true:row | true:sparse | true:recovery | true:fastboot | false | 1)
        echo "BACKUP_ORIGINAL_SUPER finde and have $BACKUP_ORIGINAL_SUPER" &>>$LOG
        ;;
    *)
        my_print "BACKUP_ORIGINAL_SUPER Has an incorrect value"
        return 1
        ;;
    esac
    case "$DFE_PATCH" in
    true | false | 1 | 0)
        echo "DFE_PATCH finde and have $DFE_PATCH" &>>$LOG
        ;;
    *)
        my_print "DFE_PATCH Has an incorrect value"
        return 1
        ;;
    esac
    case "$ALLOW_DIRECT_SUPER_FLASH" in
    true | false | 1 | 0) echo "ALLOW_DIRECT_SUPER_FLASH has $ALLOW_DIRECT_SUPER_FLASH" &>>$LOG ;;
    *) my_print "ALLOW_DIRECT_SUPER_FLASH has an incorrect value"; return 1 ;;
    esac
    case "$ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH" in
    true | false | 1 | 0) echo "ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH has $ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH" &>>$LOG ;;
    *) my_print "ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH has an incorrect value"; return 1 ;;
    esac
    case "$ABORT_ON_ACTIVE_SNAPSHOT" in
    true | false | 1 | 0) echo "ABORT_ON_ACTIVE_SNAPSHOT has $ABORT_ON_ACTIVE_SNAPSHOT" &>>$LOG ;;
    *) my_print "ABORT_ON_ACTIVE_SNAPSHOT has an incorrect value"; return 1 ;;
    esac
    case "$DROP_STALE_COW_PARTITIONS" in
    true | false | 1 | 0) echo "DROP_STALE_COW_PARTITIONS has $DROP_STALE_COW_PARTITIONS" &>>$LOG ;;
    *) my_print "DROP_STALE_COW_PARTITIONS has an incorrect value"; return 1 ;;
    esac
    case "$ALLOW_STAGED_BUILD_WITH_STALE_COW" in
    true | false | 1 | 0) echo "ALLOW_STAGED_BUILD_WITH_STALE_COW has $ALLOW_STAGED_BUILD_WITH_STALE_COW" &>>$LOG ;;
    *) my_print "ALLOW_STAGED_BUILD_WITH_STALE_COW has an incorrect value"; return 1 ;;
    esac
    case "$LOCKED_BOOTLOADER_FLASH_GUARD" in
    true | false | 1 | 0) echo "LOCKED_BOOTLOADER_FLASH_GUARD has $LOCKED_BOOTLOADER_FLASH_GUARD" &>>$LOG ;;
    *) my_print "LOCKED_BOOTLOADER_FLASH_GUARD has an incorrect value"; return 1 ;;
    esac
    case "$ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH" in
    true | false | 1 | 0) echo "ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH has $ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH" &>>$LOG ;;
    *) my_print "ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH has an incorrect value"; return 1 ;;
    esac
    case "$CHECK_GROUP_LIMITS" in
    true | false | 1 | 0) echo "CHECK_GROUP_LIMITS has $CHECK_GROUP_LIMITS" &>>$LOG ;;
    *) my_print "CHECK_GROUP_LIMITS has an incorrect value"; return 1 ;;
    esac
    case "$PATCH_FSTAB_RW_ONLY" in
    true | false | 1 | 0) echo "PATCH_FSTAB_RW_ONLY has $PATCH_FSTAB_RW_ONLY" &>>$LOG ;;
    *) my_print "PATCH_FSTAB_RW_ONLY has an incorrect value"; return 1 ;;
    esac
    case "$BACKUP_BEFORE_SNAPSHOT_ABORT" in
    true | false | 1 | 0) echo "BACKUP_BEFORE_SNAPSHOT_ABORT has $BACKUP_BEFORE_SNAPSHOT_ABORT" &>>$LOG ;;
    *) my_print "BACKUP_BEFORE_SNAPSHOT_ABORT has an incorrect value"; return 1 ;;
    esac
    case "$SNAPSHOT_ABORT_BACKUP_MODE" in
    sparse | fastboot | row | raw | recovery) echo "SNAPSHOT_ABORT_BACKUP_MODE has $SNAPSHOT_ABORT_BACKUP_MODE" &>>$LOG ;;
    *) my_print "SNAPSHOT_ABORT_BACKUP_MODE has an incorrect value"; return 1 ;;
    esac
    case "$OPLUS_RECLAIM_MODE" in
    true | false | 1 | 0) echo "OPLUS_RECLAIM_MODE has $OPLUS_RECLAIM_MODE" &>>$LOG ;;
    *) my_print "OPLUS_RECLAIM_MODE has an incorrect value"; return 1 ;;
    esac
    case "$RECLAIM_INCLUDE_MY_MANIFEST" in
    true | false | 1 | 0) echo "RECLAIM_INCLUDE_MY_MANIFEST has $RECLAIM_INCLUDE_MY_MANIFEST" &>>$LOG ;;
    *) my_print "RECLAIM_INCLUDE_MY_MANIFEST has an incorrect value"; return 1 ;;
    esac
    case "$ALLOW_RECLAIM_WITH_SNAPSHOT" in
    true | false | 1 | 0) echo "ALLOW_RECLAIM_WITH_SNAPSHOT has $ALLOW_RECLAIM_WITH_SNAPSHOT" &>>$LOG ;;
    *) my_print "ALLOW_RECLAIM_WITH_SNAPSHOT has an incorrect value"; return 1 ;;
    esac
    case "$WHAT_DO_SCRIPT" in
    fullrw | literw | checkrw)
        echo "WHAT_DO_SCRIPT finde and have $WHAT_DO_SCRIPT" &>>$LOG
        ;;
    *)
        my_print "WHAT_DO_SCRIPT Has an incorrect value"
        return 1
        ;;
    esac
    return 0
}
literw_func() {
    local sdk_now
    sdk_now="${EFFECTIVE_ANDROID_SDK:-${ANDROID_SDK:-$(getprop ro.build.version.sdk 2>/dev/null)}}"
    if [ "${DISABLE_LITERW_BY_DEFAULT:-true}" = "true" ] && is_uint "$sdk_now" && [ "$sdk_now" -ge 36 ]; then
        my_print "LiteRW disabled on Android 16/17 guard profile; use staged FullRW via recovery/fastbootd"
        abortF 92 16017
    fi
    for part in $(check_rw_partition_lpdump); do

        i=$(resolve_partition_block "$part")

        umount -f -l $i && umount -f -l $i && umount -f -l $i &&
            umount -f -l $i && umount -f -l $i && umount -f -l $i &&
            umount -f -l $i && umount -f -l $i && umount -f -l $i

        e2fsck -f $i
        blockdev --setrw $i
        e2fsck -E unshare_blocks -y -f $i
        resize2fs $i

        case $part in
        *-cow*) echo "$part COW" &>>$LOG ;;
        *)
            mount -r $i &>>$LOG && {
                mount_for_check "$i" "$part" "LiteRW"
            } || {
                my_print "Can't mount $part. This partition is not listed in the fstab file, no mount point available"
            }
            ;;
        esac

    done
}

(mountpoint -q /data) || {
    mount /data || {
        umount /data
    }
}
(mountpoint -q /data) && {
    TMP_NEO=/data/local/TMP_NEO
    TMP_IMGS=/data/local/TMP_NEO/imgs
    NEO_LOGS=/data/media/0/NEO.LOGS
    check_size_main_path=/data
    OUT_SUPER_DIR=/data/media/0/RO2RW_SUPER
} || {
    $FORCE_START && {
        echo "Force externa Storage"
        $IF_NO_DATA_CONTINUE || abortF 75 1818
    } || {
        MYSELECT "Can't mount /data. Detected Main path :$(read_main_dir "$arg3") you can continue, External storage devices can be slow and it will be a long process" \
            "Yes. Continue"
    }
    TMP_NEO=/dev/TMP_NEO
    TMP_IMGS="$(read_main_dir "$arg3")/NEO.IMGS/imgs"
    NEO_LOGS="$(read_main_dir "$arg3")/NEO.LOGS"
    check_size_main_path=$(read_main_dir "$arg3")
    OUT_SUPER_DIR=$(read_main_dir "$arg3")/RO2RW_SUPER

}

LOG=$TMP_NEO/log.file.txt
echo "empty" >>$TMP_NEO/mount_problem.txt
PATH=$TMP_NEO/$arch:$PATH
CURRENT_SLOT_NUM=$(bootctl get-current-slot 2>/dev/null)
SLOT=$(bootctl get-suffix "$CURRENT_SLOT_NUM" 2>/dev/null)
[ -z "$SLOT" ] && SLOT=$(getprop ro.boot.slot_suffix 2>/dev/null)
case "$SLOT" in
a|b) SLOT="_$SLOT" ;;
esac
case "$SLOT" in
_a) SLOT_NUM=0 ;;
_b) SLOT_NUM=1 ;;
*) SLOT_NUM="$CURRENT_SLOT_NUM" ;;
esac
LPDUMP="$TMP_NEO/LPDUMP.txt"
mv $TMP_NEO/config.txt $TMP_NEO/config.sh

REMOVE_TIMEOUT_KEY=false

. $TMP_NEO/config.sh
# Safe defaults. config.txt may override them.
: ${ALLOW_PARTITIONS:="system system_ext product vendor odm"}
: ${DENY_PARTITIONS:="boot init_boot vendor_boot vbmeta vbmeta_system vbmeta_vendor pvmfw misc metadata userdata cache modem* bluetooth* abl* xbl* aop* tz* hyp* keymaster* qupfw* uefisecapp* devcfg* dsp* *_dlkm *_firmware oplus* my_* reserve* cust*"}
: ${PATCH_FBE_FLAGS:=true}
: ${PATCH_AVB_FLAGS:=false}
: ${PATCH_STORAGE_FLAGS:=false}
: ${SCOPED_FSTAB_PATCH:=true}
: ${DISABLE_LITERW_BY_DEFAULT:=true}
: ${ALLOW_DIRECT_SUPER_FLASH:=false}
: ${ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH:=false}
: ${ABORT_ON_ACTIVE_SNAPSHOT:=true}
: ${DROP_STALE_COW_PARTITIONS:=true}
: ${ALLOW_STAGED_BUILD_WITH_STALE_COW:=true}
: ${LOCKED_BOOTLOADER_FLASH_GUARD:=true}
: ${ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH:=false}
: ${BACKUP_BEFORE_SNAPSHOT_ABORT:=true}
: ${SNAPSHOT_ABORT_BACKUP_MODE:=sparse}
: ${CHECK_GROUP_LIMITS:=true}
: ${PATCH_FSTAB_RW_ONLY:=true}
: ${LP_METADATA_SIZE:=65536}
: ${TARGET_FS_FROM_EXT4:=f2fs}
: ${TARGET_FS_FROM_EROFS:=ext4}
: ${TARGET_FS_FROM_F2FS:=f2fs}
: ${TARGET_FS_FROM_OTHER:=ext4}
: ${REQUIRE_F2FS_TOOLS:=true}
: ${F2FS_IMAGE_EXTRA_MB:=160}
: ${F2FS_POPULATE_MODE:=auto}
: ${ALLOW_F2FS_MOUNTCOPY_FALLBACK:=true}
: ${F2FS_IMAGE_SIZE_POLICY:=source}
: ${F2FS_FALLBACK_COPY_MODE:=auto}
f2fs_re=false
: ${AUTO_INSTALL_MODE:=false}
: ${AUTO_CRITICAL_PROMPTS:=true}
: ${AUTO_PROMPT_APP_REMOVAL:=true}
: ${AUTO_STAGED_OUTPUT:=sparse}
SUPER_WRITE_MODE="unknown"
normalize_bool_vars FORCE_START AUTO_INSTALL_MODE AUTO_CRITICAL_PROMPTS AUTO_PROMPT_APP_REMOVAL REMOVE_TIMEOUT_KEY IF_VALUE_WRONG IF_NO_DATA_CONTINUE IF_EXT4_MOUNT_PROBLEM_CONTINUE DFE_PATCH ALLOW_DFE_PATCH SAFE_COLOROS_MODE INCLUDE_UNSLOTTED_PARTITIONS STRICT_LPDUMP_PARTITION_PARSE AUTO_BACKUP_METADATA PATCH_FBE_FLAGS PATCH_AVB_FLAGS PATCH_STORAGE_FLAGS SCOPED_FSTAB_PATCH DISABLE_LITERW_BY_DEFAULT ALLOW_DIRECT_SUPER_FLASH ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH ABORT_ON_ACTIVE_SNAPSHOT DROP_STALE_COW_PARTITIONS ALLOW_STAGED_BUILD_WITH_STALE_COW LOCKED_BOOTLOADER_FLASH_GUARD ALLOW_LOCKED_BOOTLOADER_DIRECT_FLASH CHECK_GROUP_LIMITS PATCH_FSTAB_RW_ONLY SNAPSHOT_REPORT_ONLY BACKUP_BEFORE_SNAPSHOT_ABORT OPLUS_RECLAIM_MODE RECLAIM_INCLUDE_MY_MANIFEST ALLOW_RECLAIM_WITH_SNAPSHOT REQUIRE_F2FS_TOOLS ALLOW_F2FS_MOUNTCOPY_FALLBACK
if is_true "$AUTO_INSTALL_MODE"; then
    FORCE_START=true
    WHAT_DO_SCRIPT="fullrw"
    BACKUP_ORIGINAL_SUPER="true:sparse"
    ALLOW_DIRECT_SUPER_FLASH=false
    ALLOW_UNSAFE_ANDROID16_DIRECT_FLASH=false
    DFE_PATCH=false
    ALLOW_DFE_PATCH=false
    OPLUS_RECLAIM_MODE=false
    RECLAIM_INCLUDE_MY_MANIFEST=false
    ALLOW_RECLAIM_WITH_SNAPSHOT=false
    DROP_STALE_COW_PARTITIONS=true
    ALLOW_STAGED_BUILD_WITH_STALE_COW=true
    LOCKED_BOOTLOADER_FLASH_GUARD=true
    PATCH_FSTAB_RW_ONLY=true
    DISABLE_LITERW_BY_DEFAULT=true
    SAFE_COLOROS_MODE=true
    RW_SIZE_MOD="MAX"
    [ -z "$RW_SIZE" ] && RW_SIZE="S=70% V=10% P=10% SE=5% OT=5%"
    case "$AUTO_STAGED_OUTPUT" in sparse|fastboot|row|raw|recovery) : ;; *) AUTO_STAGED_OUTPUT="sparse" ;; esac
fi

ANDROID_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
DEVICE_BRAND="$(getprop ro.product.brand 2>/dev/null)"
DEVICE_MANUFACTURER="$(getprop ro.product.manufacturer 2>/dev/null)"
ROM_FLAVOR="$(getprop ro.build.version.opporom 2>/dev/null)$(getprop ro.oplus.version 2>/dev/null)$(getprop ro.build.version.realmeui 2>/dev/null)"
case "$(echo "$DEVICE_BRAND $DEVICE_MANUFACTURER $ROM_FLAVOR" | tr '[:upper:]' '[:lower:]')" in
*oppo*|*oplus*|*oneplus*|*realme*|*coloros*) IS_OPLUS_FAMILY=true ;;
*) IS_OPLUS_FAMILY=false ;;
esac

case "$FORCE_START" in
true | false | 1 | 0)
    echo "FORCE_START finde and have $FORCE_START" &>>$LOG
    ;;
*)
    my_print "FORCE_START Has an incorrect value"
    abortF 122 814
    ;;
esac

$terminal_on && {
    FORCE_START=false
}
ui_print " "
ui_print " "
ui_print " "
ui_print "*******************"
my_print "Welcome to SuperForgeRW Nexus v4.4.5-f2fs-hardfix | AutoFS ext4->F2FS + safe fallback"
ui_print "*******************"
my_print "Aka RO2RW revived / SuperForgeRW unified / EROFS2EXT4"
ui_print "*******************"
my_print "$RSTATUS$VER" # prebuild for MFP NEO inbuild function with more functional"
ui_print "*******************"
my_print "Base by @LeeGarChat | v4.4.5 fixes sload_f2fs exit=134 via safe fallback and drop-in F2FS tools"
ui_print "*******************"
my_print "ARCH: $arch"
my_print "Active slot: $([ -z "$SLOT" ] && echo "A-only" || echo "$SLOT")"
my_print "Force start: $FORCE_START"
my_print "Auto install mode: $AUTO_INSTALL_MODE"
my_print "Android target release/API: ${ANDROID_RELEASE:-unknown}/${ANDROID_SDK:-unknown}"
my_print "Recovery SDK / effective guard SDK: ${RECOVERY_SDK:-unknown}/${EFFECTIVE_ANDROID_SDK:-unknown}"
my_print "OPlus/ColorOS family detected: $IS_OPLUS_FAMILY"
my_print "DFE allowed by config: $ALLOW_DFE_PATCH"
my_print "AutoFS target policy: ext4->$TARGET_FS_FROM_EXT4 erofs->$TARGET_FS_FROM_EROFS f2fs->$TARGET_FS_FROM_F2FS other->$TARGET_FS_FROM_OTHER"
my_print "F2FS tools required: $REQUIRE_F2FS_TOOLS | populate=$F2FS_POPULATE_MODE | fallback=$ALLOW_F2FS_MOUNTCOPY_FALLBACK | size_policy=$F2FS_IMAGE_SIZE_POLICY"
preflight_f2fs_tools_policy
ui_print " "
my_print "Paths directories:"
my_print "TMP_NEO = $TMP_NEO"
my_print "TMP_IMGS = $TMP_IMGS"
my_print "NEO_OUT_LOGS = $NEO_LOGS"
my_print "Main_dir = $check_size_main_path"
my_print "OUT_SUPER_DIR = $OUT_SUPER_DIR"
ui_print " "
ui_print " "

$FORCE_START && {
    chek_value || {
        $IF_VALUE_WRONG && {
            MYSELECT "Which of the values was incorrect, do you want to continue in manual tuning mode?" \
                "Continue"
            FORCE_START=false
            REMOVE_TIMEOUT_KEY=false
        } || {
            abortF 200 11234
        }

    }
}

case $RW_SIZE_MOD in
MAX)
    sleep 0.1
    ;;
FIXED)
    sleep 0.1
    ;;
*)
    my_print "RW_SIZE_MOD Has an incorrect value"
    abortF 122 811
    ;;
esac

if (find_block super "super$SLOT" "super_${SLOT#_}" &>/dev/null); then
    my_print "Super found"
    SUPER_PATH=$(find_block super "super$SLOT" "super_${SLOT#_}")
else
    my_print "Can't find super partition. SuperForgeRW only works on dynamic-super devices"
    exit 124
fi

# fi

run_lpdump_cmd "$TMP_NEO/$arch/lpdump" "$SUPER_PATH" &>>$LOG && {
    lpdump_bin=$TMP_NEO/$arch/lpdump
} || {
    run_lpdump_cmd "/bin/lpdump" "$SUPER_PATH" &>>$LOG && {
        lpdump_bin=/bin/lpdump
    } || {
        my_print "Can't read metadata super partition"
        abortF 56 754
    }
}
run_lpdump "$SUPER_PATH" >>$TMP_NEO/LPDUMP.txt || {
    my_print "Can't read metadata super partition and write to LPDUMP.txt"
    abortF 55 759
}

mkdir -p $TMP_IMGS &>>$LOG

Ss=$(for i in $(run_lpdump "$SUPER_PATH" | grep "Size:" | busybox awk '{print $2}'); do $(calc_int "$i>20") && echo $i && break; done)
echo "Size max super:$Ss" &>>$LOG

if (check_free_data); then
    echo fine &>>$LOG
else
    my_print "Still need $(calc "($Ss/1024/1024/1024)+1") GB+ internal storage memory for continue"
    abortF 55 772
fi
if (resolve_partition_block "system$SLOT" "system" >>/dev/null); then
    my_print "Found system mapper block"
else
    my_print "Can't find mapper block"
    abortF 26 764
fi
ui_print " "
ui_print " "
td=$(run_lpdump "$SUPER_PATH")
td="${td#*Partition table:}"
preflight_dynamic_super

$FORCE_START && {
    case $WHAT_DO_SCRIPT in
    literw | LITERW | LiteRW)
        echo "Starting LiteRW" &>>$LOG
        $terminal_on && {
            my_print "LiteRW is not available inside the running system"
            abortF 1 8123
        }
        literw_func
        abortS
        ;;
    FULLRW | FullRW | fullrw)
        echo "Starting FullRW" &>>$LOG
        ;;
    CHECKRW | CheckRW | checkrw)
        echo "Starting CheckRW" &>>$LOG
        check_rw_func
        abortS
        ;;
    *)
        my_print "Incorrect value FORCE_START"
        ;;

    esac

} || {
    MYSELECT "You want make/install new RW super or check RW and free size?" \
        "Make/Install" "Check free size" "$($terminal_on || echo "Run LiteRW for recovery only")"
    case $? in
    2)
        check_rw_func
        abortS
        ;;
    3)
        literw_func
        abortS
        ;;
    esac

    set_config_for_expand
    while true; do
        MYSELECT "Confing for expand: $RW_SIZE_MOD $RW_SIZE" \
            "Continue" "Repartition"
        case $? in
        1)
            break
            ;;
        2)
            set_config_for_expand
            ;;
        esac
    done
}

case $RW_SIZE_MOD in
MAX)
    for i in $RW_SIZE; do
        i=${i%\%*}
        case "$i" in
        SE=*) RW_SIZE_SE=${i#*SE=} ;;
        S=*) RW_SIZE_S=${i#*S=} ;;
        P=*) RW_SIZE_P=${i#*P=} ;;
        V=*) RW_SIZE_V=${i#*V=} ;;
        OT=*) RW_SIZE_OT=${i#*OT=} ;;
        esac
    done
    (calc_int "$(calc "$RW_SIZE_SE+$RW_SIZE_S+$RW_SIZE_P+$RW_SIZE_V+$RW_SIZE_OT")>100") && abortF 22 866
    ;;
esac

mkdir -p "$OUT_SUPER_DIR" &>>$LOG
rm -f "$OUT_SUPER_DIR"/super-rw-*.img "$OUT_SUPER_DIR"/super.rw.*.img &>>$LOG

$FORCE_START && {

    case $DFE_PATCH in
    true | 0 | false | 1)
        echo "DFE PATCH $DFE_PATCH" &>>$LOG
        ;;
    *)
        my_print "Incorrect value DFE_PATCH"
        ;;
    esac
} || {
    if is_true "$ALLOW_DFE_PATCH"; then
        MYSELECT "Install DFE patch?" \
            "SKIP" \
            "Yes" \
            "No"
        case $? in
        2) DFE_PATCH=true ;;
        1 | 3) DFE_PATCH=false ;;
        esac
    else
        DFE_PATCH=false
        echo "DFE prompt skipped because ALLOW_DFE_PATCH=false" &>>$LOG
    fi
}
make_img
validate_all_target_images
calc_super
validate_all_target_images
make_super
if [ "$SUPER_WRITE_MODE" = "staged" ]; then
    my_print "Staged mode complete: AutoSafe made no direct super write and no avbctl changes were applied"
    my_print "Flash generated super image manually from fastbootd only after verifying backups"
    abortS
fi
$terminal_on && {

    MYSELECT "You want to force disable verification and verity. or create vbmeta files for flashing?" \
        "Force disable" "Create vbmeta* imgs for flashing via recovery/fastboot"
    case $? in
    1)
        avbctl --force disable-verification &>>$LOG
        avbctl --force disable-verity &>>$LOG
        ;;
    2)
        mkdir $TMP_NEO/bak_vbmeta
        for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT; do
            cat "$file_vbmeta" >$TMP_NEO/bak_vbmeta/$(basename $file_vbmeta)
        done
        avbctl --force disable-verification &>>$LOG
        avbctl --force disable-verity &>>$LOG
        for file_vbmeta in /dev/block/by-name/*vbmeta*$SLOT; do
            cat "$file_vbmeta" >$OUT_SUPER_DIR/"$(basename "$file_vbmeta")".patched.img
            cat $TMP_NEO/bak_vbmeta/"$(basename $file_vbmeta)" >$file_vbmeta
        done
        ;;
    esac
} || {
    avbctl --force disable-verification &>>$LOG
    avbctl --force disable-verity &>>$LOG
}

$terminal_on || {
    my_print "If you see \"Failed to mount /part (Invalid-argument)\" then this is normal, you need to restart recovery so that the partitions are defined correctly"
}
abortS
exit 0
