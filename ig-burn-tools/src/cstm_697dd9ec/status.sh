#!/bin/bash

# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# status.sh:  This script sets the spacefm status bar to show deep size once.

cd "$(spacefm -s get current_dir)"
eval sel="$(spacefm -s get --window $1 --panel $2 --tab $3 selected_filenames)"
if [ "${sel[0]}" != "" ]; then
    ( sleep .4; spacefm -s set --window $1 --panel $2 --tab $3 statusbar_text \
                                            "Calculating..." 2>/dev/null ) &
    calcpid=$!
    deepsize="$(du -csL "${sel[@]}" 2>/dev/null)"
    if [ $? -ne 0 ]; then
        err_msg="   ! access errors !"
    fi
    deepsize="$(echo "$deepsize" | tail -n 1)"
    deepsize="${deepsize%%[[:blank:]]*}"
    (( deepsize = deepsize / 1024 ))
    (( deepsizeg = ( deepsize + 51 ) / 102 ))
    if (( deepsizeg < 10 )); then
        deepsizeg="0$deepsizeg"
    fi
    len="${#deepsizeg}"
    (( len-- ))
    deepsizeg="${deepsizeg:0:len}.${deepsizeg:len}"
    if [ "${sel[1]}" = "" ]; then
        if [ -h "${sel[0]}" ]; then
            link="$(readlink "${sel[0]}")"
            if [ -e "$link" ]; then
                lmsg="Link → $link"
            else 
                lmsg="!Link → $link (missing)"
            fi
        else
            lmsg="${sel[0]}"
        fi
    else 
        lmsg="${#sel[@]} sel"
    fi
    msg="Selected Deep Size: $deepsize M  ( $deepsizeg G )$err_msg   $lmsg"
    kill $calcpid 2>/dev/null
else
    msg="Select files/folders/links to show their deep size"
fi
spacefm -s set --window $1 --panel $2 --tab $3 statusbar_text "$msg" 2>/dev/null &

