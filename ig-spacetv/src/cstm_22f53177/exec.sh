#!/bin/bash
$fm_import
#
# IG SpaceTV ( a SpaceFM Plugin ) by IgnorantGuru
# Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   License: GPL2+
#
# SpaceTV Resume Prior

if [ ! -e ~/.mpv/spacetv/resume-last ]; then
    echo "No resume files found"
    spacefm -g --window-icon error --title "SpaceTV" \
        --label "\n    No resume files found." \
        --timeout 3 --button ok &> /dev/null &
    exit
fi

~/.mpv/spacetv/resume-last --resumepre &

