#!/bin/bash
$fm_import
#
# IG SpaceTV ( a SpaceFM Plugin ) by IgnorantGuru
# Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   License: GPL2+
#
# SpaceTV Play Video w/ Options

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

# create ~/.mpv/spacetv
links=~/.mpv/spacetv/watch_later_files
mkdir -p $links

# store window size
mkdir -p "$fm_cmd_data"
winsizefile="$fm_cmd_data/winsize"
if [ ! -e "$winsizefile" ]; then
    echo "600x250" > "$winsizefile"
fi

# get saved options
mkdir -p ~/.mpv/spacetv/watch_later_files
optsfile=~/.mpv/spacetv/.woptions
options="`head -n 1 $optsfile 2>/dev/null`"
if [ "$options" = "" ]; then
    options="$mpv_options"
    echo "$options" > $optsfile
fi
scratchfile=~/.mpv/spacetv/.wscratch

# show dialog
eval "`spacefm -g --title "Play Video With Options" --window-size "@$winsizefile" \
	    --window-icon mpv \
            --label "\nmpv options for this video:" \
            --input-large @$optsfile press button2 \
            --label "Press Help to open the mpv options manual in your browser." \
            --label "\nScratchpad: (write notes and unused options here)" \
            --editor $scratchfile $scratchfile \
            --button help spacefm -s run-task web "$help_url" \
            --button cancel --button "_Play:gtk-media-play"`"
if [ "$dialog_pressed" = "button3" ]; then
    # play video
    ~/.mpv/spacetv/resume-last --options "$dialog_inputlarge1" "${fm_files[@]}" &
else
    # restore optsfile - done because spacefm had a bug 0.9.3 and prior
    echo "$options" > $optsfile
fi

