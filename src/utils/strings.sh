#!/bin/bash

strip_slot_suffix() {
    case "$1" in
    *_a | *_b) echo "${1%??}" ;;
    *) echo "$1" ;;
    esac
}

part_base_name() {
    strip_slot_suffix "$1"
}

