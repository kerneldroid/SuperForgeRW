#!/bin/bash

migrate_files() { # $1 path block , $2 part name lpdump
    local src="$1" part_name="$2" mount_part_name source_fs target_fs srcdir
    local t_mount=auto
    local ext4_img=false
    local returnen=false
    mount_part_name="$(strip_slot_suffix "$part_name")"

    if [ "$(getenforce)" = "Enforcing" ]; then
        setenforce 0
        trap 'setenforce 1' RETURN
    fi

    source_fs="$(detect_fs_type "$src")"
    target_fs="$(target_fs_for_source "$source_fs")"
    my_print "AutoFS $part_name: source=$source_fs target=$target_fs"

    case "$source_fs:$target_fs" in
    erofs:ext4)
        t_mount=erofs
        my_print "Converting $part_name.erofs to new $part_name.ext4 RW. Waiting..."
        erofs2ext4 "$src" "$part_name" "$mount_part_name" || {
            my_print "EROFS extraction failed; fallback to mount-copy EXT4 for $part_name"
            mount2ext4 "$src" "$part_name" "$mount_part_name"
        }
        ;;
    erofs:f2fs)
        t_mount=erofs
        my_print "Converting $part_name.erofs to new $part_name.f2fs RW. Waiting..."
        extract_erofs_dir "$src" "$mount_part_name" || {
            my_print "EROFS extraction failed; fallback to mount-copy F2FS for $part_name"
            srcdir="$(mount_source_to_dir "$src" "$part_name" erofs)" || return $?
            make_f2fs_from_dir "$srcdir" "$part_name" "$mount_part_name" || abortF 73 2211
            force_umount "$srcdir"; rm -rf "$srcdir" "$TMP_IMGS/${part_name}_block.img" &>>$LOG
        }
        [ -d "$TMP_IMGS/$mount_part_name" ] && {
            make_f2fs_from_dir "$TMP_IMGS/$mount_part_name" "$part_name" "$mount_part_name" || abortF 73 2212
            rm -rf "$TMP_IMGS/$mount_part_name" &>>$LOG
        }
        ;;
    ext4:ext4)
        my_print "Copy $part_name.ext4. Waiting..."
        cat "$src" >"$TMP_IMGS/$part_name.img" || abortF 73 2221
        mark_img_fs "$TMP_IMGS/$part_name.img" ext4
        tune2fs -c "20" "$TMP_IMGS/$part_name.img" &>>$LOG || abortF 73 2222
        mkdir -p "$TMP_IMGS/$part_name" &>>$LOG
        chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS/$part_name.img"
        rw_minimize "$TMP_IMGS/$part_name.img"
        rw_expand "$TMP_IMGS/$part_name.img" $(calc "40*1024*1024") || abortF 73 2223
        try_mount -w -t ext4 "$TMP_IMGS/$part_name.img" "$TMP_IMGS/$part_name" || {
            rm -f "$TMP_IMGS/$part_name.img"; rm -rf "$TMP_IMGS/$part_name"
            my_print "Original EXT4 mount failed; fallback to EXT4 rebuild for $part_name"
            t_mount=auto; ext4_img=true
            mount2ext4 "$src" "$part_name" "$mount_part_name"
        }
        force_umount "$TMP_IMGS/$part_name"
        ;;
    ext4:f2fs)
        t_mount=ext4
        my_print "Converting $part_name.ext4 to new $part_name.f2fs RW. Waiting..."
        srcdir="$(mount_source_to_dir "$src" "$part_name" ext4)" || return $?
        make_f2fs_from_dir "$srcdir" "$part_name" "$mount_part_name" || abortF 73 2213
        force_umount "$srcdir"; rm -rf "$srcdir" "$TMP_IMGS/${part_name}_block.img" &>>$LOG
        ;;
    f2fs:f2fs)
        my_print "Copy $part_name.f2fs. Waiting..."
        cat "$src" >"$TMP_IMGS/$part_name.img" || abortF 73 2224
        mark_img_fs "$TMP_IMGS/$part_name.img" f2fs
        ;;
    *)
        my_print "Unknown source FS for $part_name; rebuilding to $target_fs via mount-copy"
        t_mount=auto
        srcdir="$(mount_source_to_dir "$src" "$part_name" auto)" || return $?
        if [ "$target_fs" = "f2fs" ]; then
            make_f2fs_from_dir "$srcdir" "$part_name" "$mount_part_name" || abortF 73 2214
        else
            mount2ext4 "$src" "$part_name" "$mount_part_name"
        fi
        force_umount "$srcdir"; rm -rf "$srcdir" "$TMP_IMGS/${part_name}_block.img" &>>$LOG
        ;;
    esac

    mkdir -p "$TMP_IMGS/$part_name" &>>$LOG
    chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS/$part_name.img" &>>$LOG
    rw_minimize "$TMP_IMGS/$part_name.img"
    rw_expand "$TMP_IMGS/$part_name.img" $(calc "40*1024*1024")
    mount_rw_image "$TMP_IMGS/$part_name.img" "$TMP_IMGS/$part_name" || abortF 1 683
    for fstab in $(list_fstab_files "$TMP_IMGS/$part_name"); do
        patch_fstab_for_rw_candidates "$fstab"
        if $DFE_PATCH; then
            DFE "$fstab"
            echo '#'RO2RW $RSTATUS$VER included DFE'' >>$fstab
        fi
    done
    force_umount "$TMP_IMGS/$part_name"
    rw_minimize "$TMP_IMGS/$part_name.img"
}

