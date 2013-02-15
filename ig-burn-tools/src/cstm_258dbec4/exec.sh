#!/bin/bash
$fm_import    # import file manager variables (scroll down for info)
#
# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# exec.sh:  This script shows the Find In Snapshots command dialog.


mkdir -p "$fm_cmd_data"
snapshotpathfile="$fm_cmd_data/snapshotpath"
path="`head -n 1 "$snapshotpathfile" 2> /dev/null`"
if [ "$path" = "" ]; then
    eval path="~/burndisc-snapshots"
    mkdir -p $path
fi

choosersizefile="$fm_cmd_data/choosersize"
if [ ! -e "$choosersizefile" ]; then
    echo "800x600" > "$choosersizefile"
fi

eval "`spacefm -g --title "Find In Snapshots" --window-size "@$choosersizefile" \
        --label "Open a snapshot folder to search recursively:" \
        --chooser --dir "$path/." \
        --vbox --compact \
        --label --wrap "\nEnter grep search regex (case insensitive) or leave blank to find currently selected filenames:" \
        --input \
        --close-box \
        --button cancel --button ok 2>/dev/null`"

if [ "$dialog_pressed" != "button2" ]; then
    exit 0
fi

path="$dialog_chooser1_dir"
if [ -d "$path" ]; then
    echo "$path" > "$snapshotpathfile"
fi

if [ "$dialog_input1" = "" ]; then
    if [ "${fm_filenames[0]}" = "" ]; then
        exit 0
    fi
    echo "Searching for ${#fm_filenames[@]} filenames..."
    echo
    found=0
    for f in "${fm_filenames[@]}"; do
        test=`grep -Fr "$f" "$path" 2> /dev/null`
        if [ "$test" != "" ]; then
            echo "$test"
            found=1
        fi
    done
    if (( !found )); then
        echo
        echo "No matches."
    fi
else
    echo ">>> grep -ir \"$dialog_input1\" \"$path\""
    echo
    grep -ir "$dialog_input1" "$path"

    if [ $? -ne 0 ]; then
        echo
        echo "No matches."
    fi
fi
exit 0





















exit $?
# Example variables available for use: (imported by $fm_import)
# These variables represent the state of the file manager when command is run.
# These variables can also be used in command lines and in the Path Bar.

# "${fm_files[@]}"          selected files              ( same as %F )
# "$fm_file"                first selected file         ( same as %f )
# "${fm_files[2]}"          third selected file

# "${fm_filenames[@]}"      selected filenames          ( same as %N )
# "$fm_filename"            first selected filename     ( same as %n )

# "$fm_pwd"                 current directory           ( same as %d )
# "${fm_pwd_tab[4]}"        current directory of tab 4
# $fm_panel                 current panel number (1-4)
# $fm_tab                   current tab number

# "${fm_panel3_files[@]}"   selected files in panel 3
# "${fm_pwd_panel[3]}"      current directory in panel 3
# "${fm_pwd_panel3_tab[2]}" current directory in panel 3 tab 2
# ${fm_tab_panel[3]}        current tab number in panel 3

# "${fm_desktop_files[@]}"  selected files on desktop (when run from desktop)
# "$fm_desktop_pwd"         desktop directory (eg '/home/user/Desktop')

# "$fm_device"              selected device (eg /dev/sr0)  ( same as %v )
# "$fm_device_udi"          device ID
# "$fm_device_mount_point"  device mount point if mounted (eg /media/dvd) (%m)
# "$fm_device_label"        device volume label            ( same as %l )
# "$fm_device_fstype"       device fs_type (eg vfat)
# "$fm_device_size"         device volume size in bytes
# "$fm_device_display_name" device display name
# "$fm_device_icon"         icon currently shown for this device
# $fm_device_is_mounted     device is mounted (0=no or 1=yes)
# $fm_device_is_optical     device is an optical drive (0 or 1)
# $fm_device_is_table       a partition table (usually a whole device)
# $fm_device_is_floppy      device is a floppy drive (0 or 1)
# $fm_device_is_removable   device appears to be removable (0 or 1)
# $fm_device_is_audiocd     optical device contains an audio CD (0 or 1)
# $fm_device_is_dvd         optical device contains a DVD (0 or 1)
# $fm_device_is_blank       device contains blank media (0 or 1)
# $fm_device_is_mountable   device APPEARS to be mountable (0 or 1)
# $fm_device_nopolicy       policy_noauto set (no automount) (0 or 1)

# "$fm_panel3_device"       panel 3 selected device (eg /dev/sdd1)
# "$fm_panel3_device_udi"   panel 3 device ID
# ...                       (all these are the same as above for each panel)

# "fm_bookmark"             selected bookmark directory     ( same as %b )
# "fm_panel3_bookmark"      panel 3 selected bookmark directory

# "fm_task_type"            currently SELECTED task type (eg 'run','copy')
# "fm_task_name"            selected task name (custom menu item name)
# "fm_task_pwd"             selected task working directory ( same as %t )
# "fm_task_pid"             selected task pid               ( same as %p )
# "fm_task_command"         selected task command
# "fm_task_id"              selected task id
# "fm_task_window"          selected task window id

# "$fm_command"             current command
# "$fm_value"               menu item value             ( same as %a )
# "$fm_user"                original user who ran this command
# "$fm_my_task"             current task's id  (see 'spacefm -s help')
# "$fm_my_window"           current task's window id
# "$fm_cmd_name"            menu name of current command
# "$fm_cmd_dir"             command files directory (for read only)
# "$fm_cmd_data"            command data directory (must create)
#                                 To create:   mkdir -p "$fm_cmd_data"
# "$fm_plugin_dir"          top plugin directory
# tmp="$(fm_new_tmp)"       makes new temp directory (destroy when done)
#                                 To destroy:  rm -rf "$tmp"
# fm_edit "FILE"            open FILE in user's configured editor

# $fm_import                command to import above variables (this
#                           variable is exported so you can use it in any
#                           script run from this script)


# Script Example 1:

#   # show MD5 sums of selected files
#   md5sum "${fm_files[@]}"


# Script Example 2:

#   # Show a confirmation dialog using SpaceFM Dialog:
#   # http://ignorantguru.github.com/spacefm/spacefm-manual-en.html#dialog
#   # Use QUOTED eval to read variables output by SpaceFM Dialog:
#   eval "`spacefm -g --label "Are you sure?" --button yes --button no`"
#   if [[ "$dialog_pressed" == "button1" ]]; then
#       echo "User pressed Yes - take some action"
#   else
#       echo "User did NOT press Yes - abort"
#   fi


# Script Example 3:

#   # Build list of filenames in panel 4:
#   i=0
#   for f in "${fm_panel4_files[@]}"; do
#       panel4_names[$i]="$(basename "$f")"
#       (( i++ ))
#   done
#   echo "${panel4_names[@]}"


# Script Example 4:

#   # Copy selected files to panel 2
#      # make sure panel 2 is visible ?
#      # and files are selected ?
#      # and current panel isn't 2 ?
#   if [ "${fm_pwd_panel[2]}" != "" ] \
#               && [ "${fm_files[0]}" != "" ] \
#               && [ "$fm_panel" != 2 ]; then
#       cp "${fm_files[@]}" "${fm_pwd_panel[2]}"
#   else
#       echo "Can't copy to panel 2"
#       exit 1    # shows error if 'Popup Error' enabled
#   fi


# Script Example 5:

#   # Keep current time in task manager list Item column
#   # See http://ignorantguru.github.com/spacefm/spacefm-manual-en.html#sockets
#   while (( 1 )); do
#       sleep 0.7
#       spacefm -s set-task $fm_my_task item "$(date)"
#   done


# Bash Scripting Guide:  http://www.tldp.org/LDP/abs/html/index.html

# NOTE: Additional variables or examples may be available in future versions.
#       To see the latest list, create a new command script or see:
#       http://ignorantguru.github.com/spacefm/spacefm-manual-en.html#exvar

