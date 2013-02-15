#!/bin/bash
$fm_import
#
# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# exec.sh:  This script shows the Verify Disc command - requires verify.sh


mkdir -p "$fm_cmd_data"
burnerfile="$fm_cmd_data/burner"
burner="`head -n 1 "$burnerfile" 2>/dev/null`"
if [ "$burner" = "" ]; then
    burner="/dev/sr0"
    echo "$burner" > "$burnerfile"
fi
verifyfile="$fm_cmd_data/verify"
burn_verify="`head -n 1 "$verifyfile" 2> /dev/null`"
if [ "$burn_verify" = "" ]; then
    burn_verify="Verify Checksums"
fi
verify=( "Verify Checksums" "Compare To Image" "Compare To Dir" )

verbosefile="$fm_cmd_data/verbose"

i=0
unset devs
for d in /dev/*; do
    if [ "${d:0:8}" != "/dev/vcs" ] \
                && [ "${d:0:8}" != "/dev/tty" ] \
                && [ "${d:0:8}" != "/dev/ram" ] \
                && [ "${d:0:9}" != "/dev/loop" ] \
                && [ "${d:0:11}" != "/dev/hidraw" ]; then
        devs[i]="$d"
        (( i++ ))
    fi
done

settask()
{
    spacefm -s set-task --window $fm_my_window $fm_my_task $1 "$2"
}

mountburner()
{
    is_mounted="`udevil info "$burner" 2> "$viewpipe" | grep "^  is mounted:" | \
                                                        sed 's/.*: *\(.*\)/\1/'`"
    x=0
    while (( is_mounted != 1 && x < 10 )); do
        if (( x == 0 )); then
            echo "--- Mounting $burner..." > "$viewpipe"
            settask item "Mounting $burner"
        else
            sleep 2
        fi
        if (( verbose )); then
            echo ">>> udevil --quiet mount $burner" > "$viewpipe"
        fi
        udevil --quiet mount $burner > "$viewpipe" 2> "$viewpipe"
        
        is_mounted="`udevil info "$burner" 2> "$viewpipe" | grep "^  is mounted:" | \
                                                    sed 's/.*: *\(.*\)/\1/'`"
        (( x++ ))
    done
    if (( is_mounted != 1 )); then
        echo "*** Unable to mount $burner" > "$viewpipe"
        return 1
    fi
    info="`udevil info "$burner" 2> "$viewpipe"`"
    point="`echo "$info" | grep "^  mount paths:" | sed 's/.*: *\(.*\)/\1/'`"
    point="${point%%, *}"
    vollabel="`echo "$info" | grep "^  label:" | sed 's/.*: *\(.*\)/\1/'`"
    if [ ! -d "$point" ]; then
        return 1
    fi
}

eval "`spacefm -g --title "Verify Disc" \
    --hbox --compact \
        --label "Drive:" \
        --combo --expand "${devs[@]}" -- "@$burnerfile" \
    --close-box \
    --hbox --compact \
        --drop "${verify[@]}" -- "$burn_verify" \
        --check "Verbose" "@$verbosefile" \
    --close-box \
    --button cancel \
    --button "Verify:gtk-yes"`"

if [ "$dialog_pressed" != "button2" ]; then
    exit
fi

burner="$dialog_combo1"
echo "$burner" > "$burnerfile"
burn_verify="$dialog_drop1"
echo "$burn_verify" > "$verifyfile"
if [ "$dialog_check1" = "1" ]; then
    verboseopt="--verbose"
    verbose=1
else
    verboseopt=""
    verbose=0
fi

case "$burn_verify" in
    "Compare To Dir" )
        while true; do
            eval "`spacefm -g --title "Choose Compare Directory" \
                        --chooser --dir . \
                        --button cancel \
                        --button ok`"
            if [ "$dialog_pressed" != "button2" ]; then
                exit
            elif [ -d "$dialog_chooser1" ]; then
                burn_path="$dialog_chooser1"
                break
            fi
        done
        ;;
    "Compare To Image" )
        while true; do
            eval "`spacefm -g --title "Choose Compare Image" \
                        --chooser . \
                        --button cancel \
                        --button ok`"
            if [ "$dialog_pressed" != "button2" ]; then
                exit
            elif [ -f "$dialog_chooser1" ]; then
                createiso_path="$dialog_chooser1"
                break
            fi
        done
        ;;
esac

viewpipe=/dev/stdout
if ! mountburner; then
    exit 1
fi

settask item "Verify Disc"

bash "$fm_cmd_dir/verify.sh" $verboseopt "$burn_verify" "$burner" \
                                     "$burn_path" "$createiso_path" "$point"
if [ $? -eq 0 ]; then
    echo
    echo "All files are equal."
    exit 0
fi
exit 1

