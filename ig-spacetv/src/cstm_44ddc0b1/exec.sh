#!/bin/bash
$fm_import
#
# IG SpaceTV ( a SpaceFM Plugin ) by IgnorantGuru
# Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   License: GPL2+
#
# SpaceTV Options

# initial defaults only - edit current options in ~/.mpv/spacetv/.options
mpv_options="--save-position-on-quit --fullscreen"
help_url='https://github.com/mpv-player/mpv/blob/master/DOCS/man/en/options.rst'

# reject root
if [ "$(whoami)" = "root" ]; then
    echo "This command is disabled for the root user."
	spacefm -g --window-icon error --title "SpaceTV" \
            --label "\nThis command is disabled for the root user." \
            --button ok &> /dev/null &
    exit 1
fi

# store window size
mkdir -p "$fm_cmd_data"
winsizefile="$fm_cmd_data/winsize"
if [ ! -e "$winsizefile" ]; then
    echo "600x500" > "$winsizefile"
fi

# get saved options
mkdir -p ~/.mpv/spacetv/watch_later_files
optsfile=~/.mpv/spacetv/.options
options="`head -n 1 $optsfile 2>/dev/null`"
if [ "$options" = "" ]; then
    options="$mpv_options"
    echo "$options" > $optsfile
fi
scratchfile=~/.mpv/spacetv/.scratch

eval "`spacefm -g --title "SpaceTV Options" --window-size "@$winsizefile" \
            --window-icon gtk-preferences \
            --label "\nmpv options:" \
            --input-large @$optsfile press button2 \
            --label "Press Help to open the mpv options manual in your browser.  If you don't include --save-position-on-quit, then you must quit mpv with Shift+Q in order to save a resume point." \
            --label "\nScratchpad: (write notes and unused options here)" \
            --editor $scratchfile $scratchfile \
            --button help spacefm -s run-task web "$help_url" \
            --button cancel --button save`"
if [ "$dialog_pressed" = "button3" ]; then
    echo "$dialog_inputlarge1" > $optsfile
else
    # restore optsfile - done because spacefm had a bug 0.9.3 and prior
    echo "$options" > $optsfile
fi
exit
