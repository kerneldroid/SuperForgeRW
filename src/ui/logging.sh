#!/bin/bash

    ui_print() {
        echo -e "$*"
        [ -z $LOG ] || echo -e "ui_print: $*" &>>$LOG
    }

my_print() {
    text="$@"
    if [ "$1" = "selected" ]; then
        text="${text#*selected }"
        first_line=false
        new_line_comment=false
    elif [ "$1" = "commented" ]; then
        text="${text#*commented }"
        new_line_comment=true
        first_line=false
    else
        new_line_comment=false
        first_line=true
    fi
    all_char="${#text}"
    space_n=-1
    skipG="* "
    tmp_word=""
    tmp_word2=""
    tick=0
    { [ -z "$text" ] || [ "$text" = " " ]; } && first_line=false
    space="$(
        for i in $text; do space_n=$((space_n + 1)); done
        echo $space_n
    )"

    if (calc_int "$all_char>=43") && (calc_int "$space>=1"); then
        while (($tick < $space)); do
            tmp_word2="${text#$skipG}"
            tmp_word="${text%"$tmp_word2"*}"
            tick=$((tick + 1))
            if ((${#tmp_word} > 43)); then
                skipG="* "
                $first_line && {
                    $new_line_comment && ui_print "     $tmp_word" || ui_print "- $tmp_word"
                    first_line=false
                } || {
                    $new_line_comment && ui_print "     $tmp_word" || ui_print "  $tmp_word"
                }
                text="${text#*"$tmp_word"}"
            else
                skipG="${skipG}* "
                continue
            fi
        done
        $first_line && {
            $new_line_comment && ui_print "     $text" || ui_print "- $text"
            first_line=false
        } || {
            $new_line_comment && ui_print "     $text" || ui_print "  $text"
        }
    else $first_line && {
        $new_line_comment && ui_print "     $text" || ui_print "- $text"
        first_line=false
    } || {
        $new_line_comment && ui_print "     $text" || ui_print "  $text"
    }; fi
}

abortF() {
    [ -d $NEO_LOGS ] || mkdir -p $NEO_LOGS
    [ -z $LOG ] || echo "Error code $1: RO2RW internal error code $2" &>>$LOG
    logM="Fail-$VER-$(date +%T | sed 's|\:|-|g').txt"
    cat $LOG >$NEO_LOGS/$logM
    my_print "Output log: $NEO_LOGS/$logM"
    exit $1
}

abortS() {
    my_print "Complete"
    [ -d $NEO_LOGS ] || mkdir -p $NEO_LOGS &>>$LOG
    logM="Success-$VER-$(date +%T | sed 's|\:|-|g').txt"
    cat $LOG >$NEO_LOGS/$logM
    my_print "Output log $NEO_LOGS/$logM"
    rm -rf $TMP_NEO &>>/dev/null
    rm -rf $TMP_IMGS
    exit 0
}

