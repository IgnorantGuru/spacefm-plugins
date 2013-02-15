#!/bin/bash
$fm_import    # import file manager variables (scroll down for info)

# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# configure.sh:  This script shows the Configuration dialog (Configure button).


source "$fm_cmd_dir/config.sh"

winsizefile="$fm_cmd_data/config/winsize-configure"
if [ ! -e "$winsizefile" ]; then
    echo "500x500" > "$winsizefile"
fi

largetmpdir="`head -n 1 "$largetmpdirfile" 2>/dev/null`"
alarm_cmd="`head -n 1 "$alarmcmdfile" 2>/dev/null`"
burner="`head -n 1 "$burnerfile" 2>/dev/null`"

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

i=1
unset scripts
scripts[0]="Select a file to edit..."
cd "$fm_cmd_dir"
lsout="`/bin/ls -1`"
IFS_OLD="$IFS"
IFS=$'\n'
for f in $lsout; do
    scripts[i]="$f"
    (( i++ ))
done
IFS="$IFS_OLD"

verbose_init="$(head -n 1 "$verbosefile" 2>/dev/null)"

# make a pipe to send commands to the dialog
if [ -d "$smalltmp" ]; then
    cnfpipe="$smalltmp/burndisc-cnfpipe-$RANDOM"
elif [ -d "$default_tmpdir" ]; then
    cnfpipe="$default_tmpdir/burndisc-cnfpipe-$RANDOM"
else
    cnfpipe="/tmp/burndisc-cnfpipe-$RANDOM"
fi
rm -f "$cnfpipe"
mkfifo "$cnfpipe"

choose='eval "$(spacefm -g --chooser --dir "%input1" --button cancel --button ok)"; if [ "$dialog_pressed" = button2 ] && [ "$dialog_chooser1" != "" ]; then echo "set input1 $dialog_chooser1" > "CNFPIPE"; fi'
choose="${choose/CNFPIPE/$cnfpipe}"

while (( 1 )); do
    eval "`spacefm -g --title "Configure Burn Disc v$version" --window-size "@$winsizefile" \
        --hbox --compact \
        --label "Burner:" \
        --combo --expand "${devs[@]}" -- "@$burnerfile" \
        --close-box \
        --hbox --compact \
        --label "Large Temp Dir:" \
        --input "$largetmpdir" \
        --free-button :gtk-open bash -c "$choose" \
        --close-box \
        --hbox --compact \
        --label "Notify Command:" \
        --input "$alarm_cmd" \
        --close-box \
        --check "_Verbose Output" "@$verbosefile" \
        --hbox \
        --vbox \
        --label "Types:" \
        --editor "$typelist" "$typelist-tmp" \
        --close-box \
        --vbox \
        --label "Speeds:" \
        --editor "$speedlist" "$speedlist-tmp" \
        --close-box \
        --close-box \
        --drop "${scripts[@]}" -- +0 \
                bash -c "$fm_import; if [ -e '$fm_cmd_dir/%drop1' ]; then \
                fm_edit '$fm_cmd_dir/%drop1'; fi" \
                -- select drop1 "Select a file to edit..." \
        --button cancel --button save \
        --command "$cnfpipe" disable button1 $fm_editor_terminal`"
    if [ "$dialog_pressed" != "button2" ]; then
        rm -f "$typelist-tmp" "$speedlist-tmp"
        rm -f "$cnfpipe"
        exit
    fi
    largetmpdir="$dialog_input1"
    if [ "$largetmpdir" = "" ] || [ -d "$largetmpdir" ]; then
        break
    fi
    spacefm -g --label "\nInvalid temporary directory $largetmpdir\n\n(Leave blank for default)" \
        --button ok
done

reconfigure=0
if ! cmp "$typelist-tmp" "$typelist"; then
    cp -f "$typelist-tmp" "$typelist"
    reconfigure=1
fi
if ! cmp "$speedlist-tmp" "$speedlist"; then
    cp -f "$speedlist-tmp" "$speedlist"
    reconfigure=1
fi
if [ "$dialog_combo1" != "$burner" ]; then
    echo "$dialog_combo1" > "$burnerfile"
    reconfigure=1
fi
echo "$largetmpdir" > "$largetmpdirfile"
echo "$dialog_input2" > "$alarmcmdfile"
rm -f "$typelist-tmp" "$speedlist-tmp"
rm -f "$cnfpipe"
if (( reconfigure == 1 )) && [ -p "$respipe" ]; then
    echo configure > "$respipe"
fi
if [ "$verbose_init" != "$dialog_check1" ] && \
                                                        [ -p "$respipe" ]; then
    echo verbose > "$respipe"
fi
exit
