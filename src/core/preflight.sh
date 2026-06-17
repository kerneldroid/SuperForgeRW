#!/bin/bash

bootloader_flash_locked() {
    local fl ds vb
    fl="$(getprop ro.boot.flash.locked 2>/dev/null)"
    ds="$(getprop ro.boot.vbmeta.device_state 2>/dev/null)"
    vb="$(getprop ro.boot.verifiedbootstate 2>/dev/null)"
    [ "$fl" = "1" ] && return 0
    [ "$ds" = "locked" ] && return 0
    [ "$vb" = "green" ] && return 0
    return 1
}

preflight_f2fs_tools_policy() {
    f2fs_target_policy_requested || return 0
    my_print "Preflight F2FS tools check because target policy includes F2FS"
    require_f2fs_tools
}

