#!/bin/bash
# SpaceFM Dialog Example Application - see README
#    Copyright (C) 2016 IgnorantGuru <ignorantguru@gmx.com>
#
#    License: Creative Commons Attribution 4.0 International (CC BY 4.0)
#    https://creativecommons.org/licenses/by/4.0/
#
#    You are free to:
#        Share - copy and redistribute the material in any medium or format
#        Adapt - remix, transform, and build upon the material for any purpose

######################################################################
# Accept --config-dir|-c DIR on command line
$fm_import  # use this in case this script run as SpaceFM custom command
# If you run multiple instances of this application script, each should use a
# different config dir.  
if [ "$1" = "--config-dir" ] || [ "$1" = "-c" ]; then
    # config dir specified on command line
    fm_cmd_data="$2"
    shift 2
fi
if [ "$fm_cmd_data" = "" ]; then
    # not run from within SpaceFM and no config dir specified - use home dir
    fm_cmd_data=~/.spacefm-app-example
fi

######################################################################
# A convenience function to set data file defaults
set_default()  # $1=file  $2=default value
{
    val="`head -n 1 "$1" 2>/dev/null`"
    if [ "$val" = "" ]; then
        echo "$2" > "$1"
    fi
}

######################################################################
# Set Dialog Data Files
mkdir -p "$fm_cmd_data"
winsize_file="$fm_cmd_data/winsize"
set_default "$winsize_file" "700x550"  # Default dialog size
input1_file="$fm_cmd_data/input1"
drop1_def_file="$fm_cmd_data/drop1_def"
source_file="$fm_cmd_data/source"
rm -f "$source_file"

######################################################################
# Create Pipes
# cmd_pipe is used to send commands to the running dialog
cmd_pipe="$fm_cmd_data/cmd-pipe"
# action_pipe is used to process dialog actions in the main loop
action_pipe="$fm_cmd_data/action-pipe"
# viewer_pipe is used to send messages to the log in the dialog
viewer_pipe="$fm_cmd_data/viewer-pipe"
rm -f "$viewer_pipe" "$cmd_pipe" "$action_pipe"
mkfifo "$viewer_pipe"
mkfifo "$cmd_pipe"
mkfifo "$action_pipe"

######################################################################
# Prepare Dialog Data
choice_list=( "Choice A" "Choice B" "Choice C" )
# Set default drop list to Choice B
set_default "$drop1_def_file" "${choice_list[1]}"


######################################################################
# Show Dialog
spacefm -g --title "Example Application" \
        --window-size "@$winsize_file" \
        --window-icon gtk-yes \
        --hbox --compact \
            --label "Choices:" \
            --drop "${choice_list[@]}" -- "@$drop1_def_file" \
                       bash -c "echo chose > '$action_pipe'" \
        --close-box \
        --label "Enter text:" \
        --input --compact "@$input1_file" press button1 \
        --label "Log:" \
        --viewer --scroll "$viewer_pipe" \
        --button apply bash -c "echo apply > '$action_pipe'" \
        --button close source /dev/null -- \
                       bash -c "echo cancel > '$action_pipe'" -- close \
        --window-close source /dev/null -- \
                       bash -c "echo cancel > '$action_pipe'" -- close \
        --command "$cmd_pipe" > /dev/null &
# Get the running dialog's process ID
spid=$!

######################################################################
# Main Loop
# This loop responds to actions in the dialog, and also periodically
# runs blip code which updates the dialog.
delay=5  # seconds
while [ -p "$action_pipe" ] && [ -p "$cmd_pipe" ] && ps -p $spid 2>&1 >/dev/null; do
    # wait for action in pipe using timeout to run periodic blip code
	read -t $delay <> "$action_pipe"
    if [ $? -eq 0 ]; then
        action="$REPLY"
    else
        action=""
    fi

    # Get dialog values
    if [ "$action" != "" ] && [ "$action" != "cancel" ]; then
        # There is a non-cancel action, so tell dialog to create a source
        # file so we can get current dialog values
        echo "source $source_file" > "$cmd_pipe" &
        sleep 0.1  # allow time for file creation
        if [ -e "$source_file" ]; then
            # Read the source file to update dialog values (eg $dialog_input1)
            source "$source_file"
            rm -f "$source_file"
        fi
    fi
        
    # process action
    case "$action" in
        apply )
            # User pressed Apply button
            # Log a message to the dialog's viewer
            echo "Applied $dialog_input1" > "$viewer_pipe" &
            # Don't fall through to Blip code
            continue
            ;;
        chose )
            # The user made drop list choice
            # Tell dialog to set window title to choice
            echo "set title $dialog_drop1" > "$cmd_pipe" &
            # Log a message to the dialog's viewer
            echo -e "\nChose $dialog_drop1 at $(date)\n" > "$viewer_pipe" &
            # Fall through to Blip code
            ;;
        cancel )
            # The dialog was closed by user action, break main loop
            break
            ;;
    esac

    # Blip - Code placed here will run every $delay (5) seconds:
    echo "Blip..." > "$viewer_pipe" &
done

######################################################################
# Cleanup
sleep 0.2  # allow dialog process to exit
if ps -p $spid 2>&1 >/dev/null; then
    if [ -p "$cmd_pipe" ]; then
        # close dialog
        echo "close" > "$cmd_pipe" &
        sleep 1
    fi
    # make sure dialog is gone
    kill $spid 2> /dev/null
fi
rm -f "$viewer_pipe" "$cmd_pipe" "$action_pipe" "$source_file"

exit
