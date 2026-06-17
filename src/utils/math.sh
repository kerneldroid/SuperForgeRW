#!/bin/bash

calc() {
    busybox awk 'BEGIN{ print int('$1') }'
    echo -n "calc: $* = " &>>$LOG
    busybox awk 'BEGIN{ print int('$1') }' &>>$LOG
}

calc_int() {
    echo "Calc_int: $*" &>>$LOG
    if [ "$(busybox awk 'BEGIN{ if ( '$*' ) print "true" ; else print "false" }')" = "true" ]; then
        return 0
    else
        return 1
    fi
}

calc_sort() {
    case $1 in
    1 | 0)
        sort_max=20
        sort_min=10
        ;;
    2)
        sort_max=30
        sort_min=20
        ;;
    3)
        sort_max=40
        sort_min=30
        ;;
    4)
        sort_max=50
        sort_min=40
        ;;
    5)
        sort_max=70
        sort_min=50
        ;;
    6)
        sort_max=100
        sort_min=70
        ;;
    7)
        sort_max=150
        sort_min=100
        ;;
    8 | 9)
        sort_max=1000
        sort_min=150
        ;;
    esac
}

normalize_bool_vars() {
    for _bvar in "$@"; do
        eval _bval="\${$_bvar}"
        case "$(echo "$_bval" | tr '[:upper:]' '[:lower:]')" in
        true|1|yes|y|on) eval "$_bvar=true" ;;
        false|0|no|n|off|"") eval "$_bvar=false" ;;
        *) echo "Bool $_bvar has non-standard value: $_bval" &>>$LOG ;;
        esac
    done
}

is_true() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
    true | 1 | yes | y | on) return 0 ;;
    *) return 1 ;;
    esac
}

