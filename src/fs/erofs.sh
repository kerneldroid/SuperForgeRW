#!/bin/bash

extract_erofs_dir() {
    local src="$1" label="$2"
    cd "$TMP_IMGS"
    mkdir -p "$TMP_NEO/blocks" &>>$LOG
    rm -rf "$TMP_IMGS/$label" &>>$LOG
    busybox ln -sf "$src" "$TMP_NEO/blocks/$label.img" &>>$LOG
    erofs -i "$TMP_NEO/blocks/$label.img" -x -o ./ &>"$TMP_NEO/LOG.EXTRACT.${label}.txt" || {
        cat "$TMP_NEO/LOG.EXTRACT.${label}.txt" &>>$LOG
        rm -f "$TMP_NEO/blocks/$label.img" &>>$LOG
        rm -rf "$TMP_IMGS/$label" &>>$LOG
        return 1
    }
    grep -q "exception occurred while fetching" "$TMP_NEO/LOG.EXTRACT.${label}.txt" && {
        cat "$TMP_NEO/LOG.EXTRACT.${label}.txt" &>>$LOG
        rm -f "$TMP_NEO/blocks/$label.img" &>>$LOG
        rm -rf "$TMP_IMGS/$label" &>>$LOG
        return 1
    }
    cat "$TMP_NEO/LOG.EXTRACT.${label}.txt" &>>$LOG
    rm -f "$TMP_NEO/blocks/$label.img" &>>$LOG
}

erofs2ext4() {
    local src="$1" part="$2" label="$3" size
    extract_erofs_dir "$src" "$label" || return 1
    size="$(busybox du -sb "$TMP_IMGS/$label" | awk '{print int($1*2)}')"
    
    # Pre-allocate file
    set_file_size "$TMP_IMGS/$label.img" "$size"
    
    # Format the file with ext4
    mke2fs -t ext4 -L "$label" -E android_sparse "$TMP_IMGS/$label.img" &>>$LOG || return 1
    
    # Populate the filesystem from directory
    # -d directory, -q quiet
    mke2fs -d "$TMP_IMGS/$label" -t ext4 -q "$TMP_IMGS/$label.img" &>>$LOG || return 1
    rm -rf "$TMP_IMGS/$label" &>>$LOG
    mkdir -p "$TMP_IMGS/$part" &>>$LOG
    mv "$TMP_IMGS/$label.img" "$TMP_IMGS/$part.img" &>>$LOG || return 1
    mark_img_fs "$TMP_IMGS/$part.img" ext4
}

