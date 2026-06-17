#!/bin/bash

make_img() {
    all_size_for_expand=8
    td=$(cat $LPDUMP)
    td="${td#*Partition table:}"
    [ -z "$td" ] && abortF 3 536
    my_print "Detected dynamic partitions: $(check_partition_lpdump | tr '\012' ' ')"
    my_print "RW candidates: $(check_rw_partition_lpdump | tr '\012' ' ')"
    for part in $(check_partition_lpdump); do

        i=$(resolve_partition_block "$part")
        echo "$part $i" &>>$LOG
        case $part in
        *-cow*) echo "$part COW" &>>$LOG ;;
        *)
            $boot_on || force_umount_dm "$i"
            if is_rw_candidate_partition "$part"; then
                migrate_files "$i" "$part" || abortF 73 2300
                validate_rw_image "$part" || abortF 73 2301
                case $RW_SIZE_MOD in
                FIXED)
                    all_size_for_expand=$((all_size_for_expand + $RW_SIZE))
                    ;;
                esac
            else
                preserve_partition_image "$i" "$part"
            fi
            ;;
        esac

    done
    cd $TMP_NEO
    all_size_for_expand=$(calc "$all_size_for_expand*1024*1024")
}

rw_img_part_name() {
    basename "$1" | sed 's|.img$||'
}

mark_img_fs() {
    local img="$1" fs="$2" part
    part="$(rw_img_part_name "$img")"
    echo "$fs" >"$TMP_IMGS/.fs.$part"
    [ "$fs" = "f2fs" ] && f2fs_re=true
    echo "Image FS marker: $part -> $fs" &>>$LOG
}

img_fs_marker() {
    local img="$1" part fs
    part="$(rw_img_part_name "$img")"
    fs="$(cat "$TMP_IMGS/.fs.$part" 2>/dev/null)"
    [ -n "$fs" ] && { echo "$fs"; return 0; }
    detect_fs_type "$img"
}

validate_rw_image() {
    local part="$1" img="$TMP_IMGS/$part.img" fs
    [ -s "$img" ] || { my_print "Fatal: RW image missing/empty for $part"; return 1; }
    fs="$(cat "$TMP_IMGS/.fs.$part" 2>/dev/null)"
    [ -n "$fs" ] || { my_print "Fatal: FS marker missing for RW image $part"; return 1; }
    case "$fs" in
    f2fs)
        detect_f2fs_magic "$img" || { my_print "Fatal: $part target is F2FS but image has no F2FS magic"; return 1; }
        load_f2fs_tools
        if [ -n "$F2FS_FSCK_BIN" ]; then
            "$F2FS_FSCK_BIN" -f "$img" &>>$LOG || { my_print "Fatal: fsck.f2fs failed for $part"; return 1; }
        else
            echo "fsck.f2fs missing; magic-only F2FS validation for $part" &>>$LOG
        fi
        ;;
    ext4)
        tune2fs -l "$img" &>>$LOG || { my_print "Fatal: $part target is EXT4 but tune2fs cannot read image"; return 1; }
        ;;
    *)
        my_print "Fatal: unsupported RW target FS '$fs' for $part"
        return 1
        ;;
    esac
    echo "Validated RW image: $part fs=$fs size=$(stat -c%s "$img")" &>>$LOG
}

validate_all_target_images() {
    local part img count=0 rwcount=0
    for part in $(check_partition_lpdump); do
        img="$TMP_IMGS/$part.img"
        [ -s "$img" ] || { my_print "Fatal: target image missing/empty for $part"; abortF 73 2310; }
        count=$((count + 1))
        if is_rw_candidate_partition "$part"; then
            validate_rw_image "$part" || abortF 73 2311
            rwcount=$((rwcount + 1))
        fi
    done
    [ "$count" -gt 0 ] || abortF 73 2312
    [ "$rwcount" -gt 0 ] || abortF 73 2313
    my_print "Validated images: total=$count rw=$rwcount"
}

check_partition_lpdump() {
    # Full active-slot dynamic partition set. Non-RW candidates are preserved raw.
    list_target_partitions
}

check_rw_partition_lpdump() {
    list_rw_candidate_partitions
}

preserve_partition_image() {
    local src="$1" part="$2"
    [ -z "$src" ] && abortF 44 4301
    my_print "Preserving $part raw image"
    cat "$src" >"$TMP_IMGS/$part.img" || abortF 44 4302
    [ -s "$TMP_IMGS/$part.img" ] || abortF 44 4303
}

