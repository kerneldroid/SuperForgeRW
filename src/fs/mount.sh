#!/bin/bash

mount_rw_image() {
    local img="$1" dir="$2" fs
    fs="$(img_fs_marker "$img")"
    [ -z "$fs" ] && fs=auto
    try_mount -w -t "$fs" "$img" "$dir"
}

mount_ro_source() {
    local img="$1" dir="$2" fs="$3"
    [ -z "$fs" ] && fs=auto
    try_mount -r -t "$fs" "$img" "$dir"
}

force_umount() {
    local target="$1" n=0 mnt
    [ -z "$target" ] && return 0
    while [ "$n" -lt 12 ]; do
        if [ -d "$target" ]; then
            mountpoint -q "$target" || return 0
            umount -fl "$target" &>>$LOG || true
        else
            mnt="$(mount | busybox awk -v t="$target" '$1 == t {print $3; exit}')"
            [ -n "$mnt" ] || return 0
            umount -fl "$mnt" &>>$LOG || umount -fl "$target" &>>$LOG || true
        fi
        n=$((n + 1))
        sleep 0.1 2>/dev/null || true
    done
    return 0
}

force_umount_dm() {
    ticksss=0
    while (mount | grep "$1 " &>>$LOG); do
        umount -fl $1 &>>$LOG
        (($ticksss > 10)) && return 0 || ticksss=$((ticksss + 1))
    done
    return 0
}

try_mount() {
    local mode="$1" tflag="$2" fs="$3" src="$4" dst="$5" ropt fstype n
    [ -z "$dst" ] && return 1
    mkdir -p "$dst" &>>$LOG
    case "$mode" in
    -r|ro|read-only) ropt="ro" ;;
    *) ropt="rw" ;;
    esac
    if grep -q "$(basename "$dst")" "$TMP_NEO/mount_problem.txt" 2>/dev/null; then
        echo "try_mount: $dst is in mount_problem list; skip" &>>$LOG
        return 0
    fi
    for n in 1 2 3 4 5; do
        if mountpoint -q "$dst"; then return 0; fi
        if [ "$fs" = "auto" ] || [ -z "$fs" ]; then
            mount -o "$ropt" "$src" "$dst" &>>$LOG || \
            mount -o "loop,$ropt" "$src" "$dst" &>>$LOG || true
            for fstype in ext4 f2fs erofs; do
                mountpoint -q "$dst" && return 0
                mount -t "$fstype" -o "$ropt" "$src" "$dst" &>>$LOG || \
                mount -t "$fstype" -o "loop,$ropt" "$src" "$dst" &>>$LOG || true
            done
        else
            mount -t "$fs" -o "$ropt" "$src" "$dst" &>>$LOG || \
            mount -t "$fs" -o "loop,$ropt" "$src" "$dst" &>>$LOG || true
        fi
        mountpoint -q "$dst" && return 0
        sleep 0.1 2>/dev/null || true
    done
    echo "try_mount failed: mode=$mode fs=$fs src=$src dst=$dst" &>>$LOG
    return 1
}

if_mount_problem_func() {
    local src="$1" part="$2"
    force_umount "$TMP_IMGS/$part"
    force_umount "$TMP_IMGS/${part}_block"
    if $ext4_img; then
        if $FORCE_START; then
            if $IF_EXT4_MOUNT_PROBLEM_CONTINUE; then
                echo "$part" >>$TMP_NEO/mount_problem.txt
                rm -rf "$TMP_IMGS/$part" &>>$LOG
                if [ -f "$TMP_IMGS/${part}_block.img" ]; then
                    mv "$TMP_IMGS/${part}_block.img" "$TMP_IMGS/$part.img" &>>$LOG
                else
                    cat "$src" >"$TMP_IMGS/$part.img" || return 1
                fi
                mark_img_fs "$TMP_IMGS/$part.img" "$(detect_fs_type "$TMP_IMGS/$part.img" 2>/dev/null || echo ext4)"
                return 22
            fi
            abortF 72 9991
        else
            MYSELECT "There are problems with mounting images $part; continue without checking this image?" "Continue"
            echo "$part" >>$TMP_NEO/mount_problem.txt
            rm -rf "$TMP_IMGS/$part" &>>$LOG
            if [ -f "$TMP_IMGS/${part}_block.img" ]; then
                mv "$TMP_IMGS/${part}_block.img" "$TMP_IMGS/$part.img" &>>$LOG
            else
                cat "$src" >"$TMP_IMGS/$part.img" || return 1
            fi
            mark_img_fs "$TMP_IMGS/$part.img" "$(detect_fs_type "$TMP_IMGS/$part.img" 2>/dev/null || echo ext4)"
            return 22
        fi
    fi
    rm -f "$TMP_IMGS/${part}_block.img" &>>$LOG
    ui_print "\n\n"
    my_print "Failed to mount $part. Reboot recovery and retry; if it repeats, send Fail log. No super write was attempted."
    abortF 1 614
}

mount_source_to_dir() {
    local src="$1" part="$2" fs="$3" dir="$TMP_IMGS/${part}_block"
    mkdir -p "$dir" &>>$LOG
    $boot_on || force_umount "$src"
    # Source partitions are read-only input for staged rebuild. Do not tune2fs -c on dm-* source.
    [ "$fs" = "ext4" ] && tune2fs -l "$src" &>>$LOG
    mount_ro_source "$src" "$dir" "$fs" || {
        my_print "Trying to copy a block of memory and mount a copy of $part. Waiting..."
        cat "$src" >"$TMP_IMGS/${part}_block.img"
        chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS/${part}_block.img" &>>$LOG
        mount_ro_source "$TMP_IMGS/${part}_block.img" "$dir" "$fs" || {
            if_mount_problem_func "$src" "$part"
            return $?
        }
    }
    echo "$dir"
}

mount2ext4() {
    local src="$1" part="$2" label="$3" dir size_du size_wc size_part_folser
    dir="$(mount_source_to_dir "$src" "$part" "$t_mount")" || return $?
    size_du="$(busybox du -bs "$dir" | busybox awk '{print $1}')"
    size_wc="$(wc -c "$src" | busybox awk '{print $1}')"
    (calc_int "$size_du>$size_wc") && size_part_folser="$size_du" || size_part_folser="$size_wc"
    echo "$size_part_folser" &>>$LOG
    [ "$label" = "system" ] && { cp "$TMP_NEO/emptyS.img" "$TMP_IMGS/$part.img" || abortF 73 2225; } || {
        cp "$TMP_NEO/empty.img" "$TMP_IMGS/$part.img" || abortF 73 2225
        tune2fs -c "20" -L "$label" "$TMP_IMGS/$part.img" &>>$LOG
    }
    mark_img_fs "$TMP_IMGS/$part.img" ext4
    rw_expand "$TMP_IMGS/$part.img" "$(calc "$size_part_folser*2.5")"
    mkdir -p "$TMP_IMGS/$part" &>>$LOG
    chcon u:object_r:media_rw_data_file:s0 "$TMP_IMGS/$part.img"
    try_mount -w -t ext4 "$TMP_IMGS/$part.img" "$TMP_IMGS/$part" || {
        if_mount_problem_func "$src" "$part"
        return $?
    }
    busybox cp -prc "$dir"/. "$TMP_IMGS/$part"/ &>>$LOG || abortF 73 2226
    force_umount "$TMP_IMGS/$part"
    force_umount "$dir"
    rm -f "$TMP_IMGS/${part}_block.img" &>>$LOG
    rm -rf "$dir" &>>$LOG
}

list_fstab_files() {
    local root="$1" d
    if [ "${SCOPED_FSTAB_PATCH:-true}" = "true" ]; then
        for d in "$root/etc" "$root/vendor/etc" "$root/odm/etc" "$root/product/etc" "$root/system/etc"; do
            [ -d "$d" ] && find "$d" -maxdepth 1 -type f -name "*fstab*"
        done
    else
        find "$root" -type f -name "*fstab*"
    fi
}

patch_fstab_for_rw_candidates() {
    local fstab="$1" extpart fstab_name target original edit tmp
    is_true "$PATCH_FSTAB_RW_ONLY" || return 0
    my_print "Patching $(basename "$fstab") FS types for RW candidates"
    tmp="$TMP_NEO/fstab.patch.$$"
    cp -af "$fstab" "$fstab.superforgerw.fs.bak" &>>$LOG
    for extpart in $(check_rw_partition_lpdump); do
        fstab_name="$(strip_slot_suffix "$extpart")"
        target="$(cat "$TMP_IMGS/.fs.$extpart" 2>/dev/null)"
        [ -z "$target" ] && target="$(cat "$TMP_IMGS/.fs.$fstab_name" 2>/dev/null)"
        [ -z "$target" ] && continue
        busybox awk -v p="$fstab_name" -v fs="$target" '
            BEGIN { OFS="\t" }
            /^[ \t]*#/ || NF < 3 { print; next }
            { dev=$1; sub(/^.*\//, "", dev); sub(/_(a|b)$/, "", dev); mp=$2; sub(/^\/system\//, "", mp); sub(/^\//, "", mp); }
            (dev == p || mp == p || $2 == "/"p || $2 == "/system/"p) && ($3 == "erofs" || $3 == "ext4" || $3 == "f2fs") { $3=fs; print; next }
            { print }
        ' "$fstab" >"$tmp" && cat "$tmp" >"$fstab"
    done
    rm -f "$tmp" &>>$LOG
}

