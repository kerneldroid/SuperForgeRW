#!/bin/bash

make_empty_f2fs() {
    local out="$1" label="$2" sectors
    require_f2fs_tools
    sectors="$(calc "$(stat -c%s "$out")/512")"
    echo "make_f2fs target: out=$out label=$label sectors=$sectors bin=$F2FS_MKFS_BIN" &>>$LOG
    case "$(basename "$F2FS_MKFS_BIN")" in
    mkfs.f2fs)
        "$F2FS_MKFS_BIN" -f -g android -l "$label" "$out" "$sectors" &>>$LOG || \
        "$F2FS_MKFS_BIN" -f -g android -l "$label" "$out" &>>$LOG || \
        "$F2FS_MKFS_BIN" -f -l "$label" "$out" "$sectors" &>>$LOG || \
        "$F2FS_MKFS_BIN" -f -l "$label" "$out" &>>$LOG || return 1
        ;;
    *)
        "$F2FS_MKFS_BIN" -g android -l "$label" "$out" "$sectors" &>>$LOG || \
        "$F2FS_MKFS_BIN" -g android -l "$label" "$out" &>>$LOG || \
        "$F2FS_MKFS_BIN" -g android "$out" "$sectors" &>>$LOG || \
        "$F2FS_MKFS_BIN" -g android "$out" &>>$LOG || \
        "$F2FS_MKFS_BIN" "$out" "$sectors" &>>$LOG || \
        "$F2FS_MKFS_BIN" "$out" &>>$LOG || return 1
        ;;
    esac
    detect_f2fs_magic "$out" || {
        echo "make_f2fs finished but F2FS magic is absent in $out" &>>$LOG
        return 1
    }
}

resize_f2fs_image() {
    local img="$1" add="$2" new sectors
    new="$(calc "$(stat -c%s "$img")+$add")"
    echo "Resizing F2FS $img + $add Bytes to $new Bytes" &>>$LOG
    truncate -s "$new" "$img" &>>$LOG || busybox truncate -s "$new" "$img" &>>$LOG || dd if=/dev/zero of="$img" bs=1 count=0 seek="$new" &>>$LOG || return 1
    load_f2fs_tools
    if [ -n "$F2FS_RESIZE_BIN" ]; then
        sectors="$(calc "$new/512")"
        "$F2FS_RESIZE_BIN" -t "$sectors" "$img" &>>$LOG || return 1
    else
        echo "Skip F2FS expand for $img: resize.f2fs missing; keeping filesystem at mkfs-created size" &>>$LOG
        truncate -s "$(calc "$new-$add")" "$img" &>>$LOG || busybox truncate -s "$(calc "$new-$add")" "$img" &>>$LOG || true
        return 0
    fi
}

populate_f2fs_by_sload() {
    local srcdir="$1" out="$2" label="$3" opts="" ret
    load_f2fs_tools
    [ -n "$F2FS_SLOAD_BIN" ] || return 1
    [ -f "$TMP_IMGS/config/${label}_fs_config" ] && opts="$opts -C $TMP_IMGS/config/${label}_fs_config"
    [ -f "$TMP_IMGS/config/${label}_file_contexts" ] && opts="$opts -s $TMP_IMGS/config/${label}_file_contexts"
    echo "sload_f2fs opts:$opts -f $srcdir -t /$label -T 0 $out" &>>$LOG
    "$F2FS_SLOAD_BIN" $opts -f "$srcdir" -t "/$label" -T 0 "$out" &>>$LOG
    ret=$?
    echo "sload_f2fs exit=$ret for label=$label image=$out" &>>$LOG
    case "$ret" in
    0)
        ;;
    1)
        # AOSP mkf2fsuserimg treats exit=1 from sload_f2fs as non-fatal after corrections.
        echo "sload_f2fs exit=1 accepted for label=$label" &>>$LOG
        ;;
    *)
        my_print "sload_f2fs failed for $label with exit=$ret; switching to fallback if enabled"
        return 1
        ;;
    esac
    detect_f2fs_magic "$out" || return 1
}

populate_f2fs_by_mountcopy() {
    local srcdir="$1" out="$2" part="$3" mnt="$TMP_IMGS/${part}_newf2fs" ret count_src count_dst
    is_true "${ALLOW_F2FS_MOUNTCOPY_FALLBACK:-false}" || {
        my_print "F2FS fallback disabled for $part"
        return 1
    }
    my_print "F2FS fallback populate for $part: mount image and copy tree safely"
    rm -rf "$mnt" &>>$LOG
    mkdir -p "$mnt" &>>$LOG
    try_mount -w -t f2fs "$out" "$mnt" || {
        my_print "F2FS fallback failed: cannot mount $part image RW"
        rm -rf "$mnt" &>>$LOG
        return 1
    }

    # Do NOT use busybox cp -prc here. On this OrangeFox it returned Bad address.
    # Try several copy engines, preserving owners, modes, symlinks and xattrs where possible.
    ret=1
    if command -v cp >/dev/null 2>&1; then
        cp -a "$srcdir"/. "$mnt"/ &>>$LOG && ret=0
        [ "$ret" = "0" ] || cp -dpR "$srcdir"/. "$mnt"/ &>>$LOG && ret=0
    fi
    if [ "$ret" != "0" ] && command -v busybox >/dev/null 2>&1; then
        busybox cp -a "$srcdir"/. "$mnt"/ &>>$LOG && ret=0
        [ "$ret" = "0" ] || busybox cp -dpR "$srcdir"/. "$mnt"/ &>>$LOG && ret=0
    fi
    if [ "$ret" != "0" ] && command -v tar >/dev/null 2>&1; then
        (cd "$srcdir" && tar -cpf - .) | (cd "$mnt" && tar -xpf -) &>>$LOG && ret=0
    fi
    if [ "$ret" != "0" ] && command -v busybox >/dev/null 2>&1; then
        (cd "$srcdir" && busybox tar -cpf - .) | (cd "$mnt" && busybox tar -xpf -) &>>$LOG && ret=0
    fi

    sync
    count_src="$(find "$srcdir" -xdev 2>/dev/null | wc -l | tr -d ' ')"
    count_dst="$(find "$mnt" -xdev 2>/dev/null | wc -l | tr -d ' ')"
    echo "F2FS fallback tree count for $part: src=$count_src dst=$count_dst ret=$ret" &>>$LOG
    force_umount "$mnt"
    rm -rf "$mnt" &>>$LOG
    [ "$ret" = "0" ] || return 1
    [ -n "$count_src" ] && [ -n "$count_dst" ] && [ "$count_dst" -gt 1 ] || return 1
    detect_f2fs_magic "$out" || return 1
    return 0
}

make_f2fs_from_dir() {
    local srcdir="$1" part="$2" label="$3" out="$TMP_IMGS/$part.img" data_size img_size min_size src_part_size policy
    require_f2fs_tools
    rm -f "$out" &>>$LOG
    data_size="$(busybox du -bs "$srcdir" | busybox awk '{print $1}')"
    min_size="$(calc "128*1024*1024")"
    policy="${F2FS_IMAGE_SIZE_POLICY:-source}"
    src_part_size="$(get_img_size "$part" 2>/dev/null)"
    case "$policy" in
    source|partition|same)
        img_size="$src_part_size"
        # If source size is not available, fall back to data+extra.
        [ -n "$img_size" ] || img_size="$(calc "$data_size+${F2FS_IMAGE_EXTRA_MB:-160}*1024*1024")"
        ;;
    data|extra|grow)
        img_size="$(calc "$data_size+${F2FS_IMAGE_EXTRA_MB:-160}*1024*1024")"
        ;;
    *)
        img_size="$(calc "$data_size+${F2FS_IMAGE_EXTRA_MB:-160}*1024*1024")"
        ;;
    esac
    (calc_int "$img_size<$min_size") && img_size="$min_size"
    echo "F2FS sizing $part: policy=$policy source_size=$src_part_size data=$data_size extra_mb=${F2FS_IMAGE_EXTRA_MB:-160} final=$img_size" &>>$LOG
    my_print "Building $part.f2fs RW image: data=${data_size} bytes image=${img_size} bytes policy=$policy"
    set_file_size "$out" "$img_size" || return 1
    chcon u:object_r:media_rw_data_file:s0 "$out" &>>$LOG
    make_empty_f2fs "$out" "$label" || return 1
    case "$F2FS_POPULATE_MODE" in
    sload|auto|"")
        populate_f2fs_by_sload "$srcdir" "$out" "$label" || {
            if is_true "${ALLOW_F2FS_MOUNTCOPY_FALLBACK:-false}"; then
                my_print "sload_f2fs failed for $part; trying safe F2FS mount-copy fallback"
                populate_f2fs_by_mountcopy "$srcdir" "$out" "$part" || return 1
            else
                my_print "F2FS build aborted for $part: sload_f2fs failed and fallback is disabled"
                return 1
            fi
        } ;;
    mountcopy)
        populate_f2fs_by_mountcopy "$srcdir" "$out" "$part" || return 1 ;;
    *)
        my_print "Unknown F2FS_POPULATE_MODE=$F2FS_POPULATE_MODE"
        return 1 ;;
    esac
    detect_f2fs_magic "$out" || { echo "F2FS magic missing after populate for $part" &>>$LOG; return 1; }
    [ -n "$F2FS_FSCK_BIN" ] && "$F2FS_FSCK_BIN" -f "$out" &>>$LOG || true
    mark_img_fs "$out" f2fs
}

