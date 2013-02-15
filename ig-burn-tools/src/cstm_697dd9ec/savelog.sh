#!/bin/bash
$fm_import

# IG Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# savelog.sh:  This script shows the Save Log dialog (from Save Log button).


winsize="$fm_cmd_data/config/winsize-savelog"

savelogfile="$fm_cmd_data/config/savelog"
savelog="`head -n 1 "$savelogfile" 2>/dev/null`"

# get save path
while (( 1 )); do
    eval "`spacefm -g --title "Save Burn Disc Log" --window-size "@$choosersizefile" \
        --chooser --save "$savelog" \
        --button cancel --button save`"

    if [ "$dialog_pressed" != "button2" ]; then
        exit
    fi
    savelog="$dialog_chooser1"
    if [ "$dialog_chooser1" = "" ]; then
        continue
    fi
    if [ -e "$savelog" ]; then
        eval "`spacefm -g --title "File Exists" \
            --label "\nFile '$savelog' already exists.\n\nOverwrite?" \
            --button yes \
            --button no`"
        if [ "$dialog_pressed" = "button1" ]; then
            break
        fi
    else
        break
    fi
done

# save log
err=0
if [ -p "$cmdpipe" ]; then
    rm -f "$tmplogfile"
    echo "source /dev/null" > "$cmdpipe"
    sleep .5
    x=0
    while (( x < 6 )) && [ ! -e "$tmplogfile" ]; do
        sleep .5
        (( x++ ))
    done
    if [ -e "$tmplogfile" ]; then
        msg=`cp -f "$tmplogfile" "$savelog" 2>&1`
        err=$?
        rm -f "$tmplogfile"
    else
        err=1
    fi
else
    err=1
fi

if [ $err -ne 0 ]; then
    spacefm -g --window-icon error --title "Save Log Error" \
               --label --wrap "\nAn error occured saving log file $savelog\n\n$msg" \
               --button ok > /dev/null &
else
    echo "$savelog" > "$savelogfile"
fi

exit

