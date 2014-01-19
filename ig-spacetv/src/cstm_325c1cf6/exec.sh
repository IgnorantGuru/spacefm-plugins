#!/bin/bash
$fm_import
#
# IG SpaceTV ( a SpaceFM Plugin ) by IgnorantGuru
# Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   License: GPL2+
#
# SpaceTV Play Video

# reject root
if [ "$(whoami)" = "root" ]; then
    echo "This command is disabled for the root user."
	spacefm -g --window-icon error --title "SpaceTV" \
            --label "\nThis command is disabled for the root user." \
            --button ok &> /dev/null &
    exit 1
fi

if [ "$(which mpv)" = "" ]; then
    echo "The SpaceTV plugin requires mpv to be installed."
	spacefm -g --window-icon error --title "SpaceTV" \
            --label "\nThe SpaceTV plugin requires mpv to be installed." \
            --button ok &> /dev/null &
    exit 1
fi
	
# create ~/.mpv/spacetv
links=~/.mpv/spacetv/watch_later_files
mkdir -p $links

# link the spacetv.sh for use by the Resume Last and Prior commands
# and by system-wide shortcuts
if [ "$(readlink ~/.mpv/spacetv/resume-last 2>/dev/null)" != \
					"$fm_cmd_dir/spacetv.sh" ]; then
    ln -sf "$fm_cmd_dir/spacetv.sh" ~/.mpv/spacetv/resume-last
fi

# play video
"$fm_cmd_dir/spacetv.sh" "${fm_files[@]}" &


