#!/bin/bash
#
# IG SpaceTV ( a SpaceFM Plugin ) by IgnorantGuru
# Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   License: GPL2+
#
# SpaceTV script to play or resume video
#
# This spacetv.sh script may also be used independently of SpaceFM to play
# videos, or resume the last (--resumelast) or prior (--resumepre) videos.
# To pass it mpv options, use --options OPTIONS as the first argument.
# This script only requires mpv, not SpaceFM.

# initial defaults only - edit current options in ~/.mpv/spacetv/.options
mpv_options="--save-position-on-quit --fullscreen"

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
cat << EOF
SpaceTV 0.5   Copyright (C) 2014 IgnorantGuru <ignorantguru@gmx.com>   GPL2+
Plays videos in mpv with resume.  
    Usage: spacetv.sh [--options OPTIONS] FILE ...
    Usage: spacetv.sh --resumelast
    Usage: spacetv.sh --resumepre

    Options must precede files on the command line.  OPTIONS are mpv options.
    Global options are saved in ~/.mpv/spacetv/.options

    https://github.com/IgnorantGuru/spacefm-plugins/blob/master/ig-spacetv/

EOF
    exit
fi

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

# get saved options
optsfile=~/.mpv/spacetv/.options
options="`head -n 1 $optsfile 2>/dev/null`"
if [ "$options" = "" ]; then
    options="$mpv_options"
    echo "$options" > $optsfile
fi

# get custom options
if [ "$1" = "--options" ]; then
    options="$2"
    shift 2
fi

# get resume options
if [ "$1" = "--resumepre" ]; then
    resumepre=1
    resume=1
    shift
elif [ "$1" = "--resumelast" ] || [ "$1" = "" ]; then
    resume=1
    shift
fi

if (( resume == 1 )); then
    # find last played incomplete file
    cd "$links"
    lastresume=`/bin/ls -1t 2> /dev/null | head -n 1`
    
    if (( resumepre == 1 )) && [ "$lastresume" != "" ]; then
        touch -h --date="2000-01-01 00:00" "$links/$lastresume"
        lastresume=`/bin/ls -1t 2> /dev/null | head -n 1`
    fi
    
    if [ "$lastresume" = "" ]; then
        echo "No resume files found"
        spacefm -g --window-icon error --title "SpaceTV" \
            --label "\n    No resume files found." \
            --timeout 3 --button ok &> /dev/null &
        exit
    fi
    resumefile="$(readlink "$links/$lastresume")"
    while [ "$1" != "" ]; do
        shift
    done
else
    resumefile=""
    if [ "$2" = "" ] && [ -h "$1" ] && [ "$(dirname "$1")" = "$links" ]; then
        # opening resume file link - resolve
        resumefile="$(readlink "$1")"
        shift
    fi
fi

if [ "$resumefile" = "" ] && [ "$1" = "" ]; then
    exit
fi

# play video

# get video filename
if [ "$resumefile" != "" ]; then
    base="$(basename "$resumefile")"
else
    base="$(basename "$1")"
fi

# add any conditional options based on file extension, etc here:
extra_options=""

# play video in mpv
echo "spacetv: mpv $options $extra_options --quiet" "$resumefile" "$@"
out="`mpv $options $extra_options --quiet "$resumefile" "$@"`"
if [ "$out" = "" ]; then
    exit
fi
echo "$out"

# save last played incomplete file?
if [ "$resumefile" != "" ] || [ "$2" = "" ]; then
    # only one file played
    if [ "$out" = "${out/Exiting... (End of file)/}" ]; then
        # end not reached - save as last played incomplete file
        if [ "$1" != "" ]; then
            resumefile="$1"
        fi
        ln -sf "$resumefile" $links/"$base"
    else
		# end reached - remove link
        rm -f $links/"$base"
    fi
fi

# delete resume files older than 60 days - enable if desired
#find -L ~/.mpv/watch_later -maxdepth 1 -type f -mtime +60 -execdir rm {} \;

# delete resume links older than 60 days
find -H $links -maxdepth 1 -type f -mtime +60 -execdir rm {} \;



