#!/bin/bash
$fm_import

# IG Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# exec.sh:  This script shows the Burn Disc dialog and conducts the burn.


# Are we running from spacefm ?
if [ "$fm_import" = "" ] || [ "$fm_my_window" = "" ] || [ "$fm_my_task" = "" ]; then
    echo "This script is designed to be run as a SpaceFM custom command script"
    exit 1
fi

# setup and read config
source "$fm_cmd_dir/config.sh"

# check dependencies - may exit
source "$fm_cmd_dir/depends.sh"

# include burn functions
source "$fm_cmd_dir/burn.sh"

# make temp dir
smalltmp="`mktemp -d --tmpdir="$tmpdir" "burndisc-$(whoami)-XXXXXXXX.tmp"`"
if [ $? -ne 0 ] || [ ! -d "$smalltmp" ]; then
    echo
    echo "Unable to create temp dir in $tmpdir"
    exit 1
fi
chmod go-rwx "$smalltmp"
export smalltmp

# config and temp files
media_last_type=X
copydiscfile="$fm_cmd_data/config/copydisc"
verifyfile="$fm_cmd_data/config/verify"
monsrc="$smalltmp/burndisc-monsrc"
tmplogfile="$smalltmp/burndisc-logfile.tmp"
export tmplogfile
checksumsfile="$fm_cmd_data/config/checksums"
checksums_init="`head -n 1 "$checksumsfile" 2>/dev/null`"
if [ "$checksums_init" = "" ]; then
    checksums_init=1
fi
imagepathfile="$fm_cmd_data/config/imagepath"
tmpiso_path=""
snapshotpathfile="$fm_cmd_data/config/snapshotpath"
saveimagepathfile="$fm_cmd_data/config/saveimagepath"
verbose="`head -n 1 "$verbosefile" 2>/dev/null`"
winsizefile="$fm_cmd_data/config/winsize"
if [ ! -e "$winsizefile" ]; then
    echo "800x600" > "$winsizefile"
fi

# pipes
# make a pipe to show output
viewpipe="$smalltmp/burndisc-viewpipe"
rm -f "$viewpipe"
mkfifo "$viewpipe"
export viewpipe

# make a pipe to send commands to the dialog
cmdpipe="$smalltmp/burndisc-cmdpipe"
rm -f "$cmdpipe"
mkfifo "$cmdpipe"
export cmdpipe

# make a pipe to receive responses
respipe="$smalltmp/burndisc-respipe"
rm -f "$respipe"
mkfifo "$respipe"
export respipe

getsrc()
{
    if [ ! -e "$cmdpipe" ]; then
        return 1
    fi
    rm -f "$monsrc"
    echo "source $monsrc" > "$cmdpipe"
    sleep .05
    x=0
    while (( x < 6 )) && [ ! -e "$monsrc" ]; do
        sleep .1
        (( x++ ))
    done
    if [ ! -e "$monsrc" ]; then
        return
    fi
    source "$monsrc"
    rm -f "$monsrc"
    if [ "$dialog_input1" = "/" ]; then
        burn_path=""
    else
        burn_path="$dialog_input1"
    fi
    burn_job="$dialog_drop1_index"
    burn_type="$dialog_combo1"
    burn_speed="$dialog_combo2"
    burn_label="$dialog_input2"
    burn_checksums="$dialog_check1"
    burn_snapshot="$dialog_check2"
    burn_saveimage="$dialog_check3"
    burn_verify="$dialog_drop2"
    burn_progress="$dialog_progress1"
}

getdisc()
{
    burner="`head -n 1 "$burnerfile"`"
    info="`ps -Af | grep -v grep | grep "/burn.sh .* --burniso $burner"`"
    if [ ! -b "$burner" ] || [ "$info" != "" ]; then
        media_type=""
        media_status=""
        media_free=0
        media_mfree=0
        blocksize=$default_blocksize
        if (( blocksize == 0 )); then
            blocksize=2048
        fi
        if [ ! -b "$burner" ]; then
            echo -e "\n*** Please configure a valid burner drive\n" > "$viewpipe"
        else
            echo "*** Drive $burner in use?" > "$viewpipe"
        fi
    else
        echo -e "--- Reading changed disc in $burner..." > "$viewpipe"
        
        # udevil info
        if (( verbose )); then
            echo ">>> udevil info \"$1\"" > "$viewpipe"
        fi
        info="`udevil info "$1" 2> "$viewpipe"`"
        blocksize="`echo "$info" | grep -m 1 "^  block size:" | sed 's/.*: *\(.*\)/\1/'`"
        if (( blocksize == 0 )); then
            blocksize=$default_blocksize
        else
            if (( blocksize != default_blocksize )); then
                echo "     *** unusual block size $blocksize" > "$viewpipe"
            fi
        fi
        if (( blocksize == 0 )); then
            blocksize=2048
        fi
        if (( verbose )); then
            echo "blocksize=$blocksize" > "$viewpipe"
        fi
        media_label="`echo "$info" | grep -m 1 "^  label:" | sed 's/.*: *\(.*\)/\1/'`"
        # trim trailing spaces
        len="${#media_label}"
        (( len-- ))
        while [[ $"${media_label:len:1}" = " " ]]; do
            media_label="${media_label:0:len}"
            len=${#media_label}
            (( len-- ))
        done

        # cdrecord info
        if (( verbose )); then
            echo ">>> $cdrecord dev=\"$1\" -media-info 2> /dev/null" > "$viewpipe"
        fi
        info="`$cdrecord dev="$1" -media-info 2> /dev/null`"
        if (( verbose )); then
            echo "$info" > "$viewpipe"
        fi
        media_type="`echo "$info" | grep -m 1 "^Mounted media type:" | sed 's/Mounted media type: *\([A-Za-z\+\/-]*\) *.*/\1/'`"
        media_status="`echo "$info" | grep -m 1 "^disk status:" | sed 's/disk status: *\(.*\)/\1/'`"
        media_free="`echo "$info" | grep -m 1 "^Remaining writable size:" | sed 's/Remaining writable size: *\(.*\)/\1/'`"
        if [ "$media_status" = "" ]; then
            echo -n "     *** no disc?" > "$viewpipe"
        else
            echo -n "     $media_status" > "$viewpipe"
            if [ "$media_status" != "empty" ] && [ "$media_type" != "" ]; then
                # show size of disc if it were blank
                getmediafree "$media_type"
                blocksize=2048
            elif [ "$media_status" = "empty" ] && [ "$media_free" = "" ]; then
                # No "Remaining writable size" so try to get free sectors
                media_free="`echo "$info" | grep -m 1 " *1 *1 *Blank *0 *[0-9]* " | sed 's/ *1 *1 *Blank *0 *\([0-9]*\) .*/\1/'`"
            fi
        fi
        if [ "$media_type" != "${media_type#BD}" ] && \
                        [ "$media_type" = "${media_type%DL}" ] && \
                        (( media_free > bdrlimit + 100000 )); then
            # help detection of DL
            media_type="$media_type/DL"
        fi
        if [ "$media_type" = "" ]; then
            if [ "$media_status" != "" ]; then
                echo -n " - no disc?" > "$viewpipe"
            fi
        else
            echo -n " $media_type" > "$viewpipe"
        fi
        (( media_free = media_free * blocksize ))
        (( media_mfree = media_free / 1024 / 1024 ))
        if [ "$media_status" = "" ] && (( media_free == 0 )); then
            echo > "$viewpipe"
        else
            echo "  ( $media_mfree M free )" > "$viewpipe"
        fi
    fi
    if [ "$media_type" != "$media_last_type" ]; then
        if [ "$media_type" = "" ]; then
            echo "set combo1 unknown" > "$cmdpipe"
        else
            echo "set combo1 $media_type" > "$cmdpipe"
        fi
        media_last_type="$media_type"
    fi
    getdisc_time=`date +%s`
}

settask()
{
    spacefm -s set-task --window $fm_my_window $fm_my_task $1 "$2"
}

showmsg()    # $1 = msg  $2 = title $3 = icon
{
    if [ "$2" != "" ]; then
        title="$2"
    else
        title="Burn Disc"
    fi
    if [ "$3" != "" ]; then
        icon="$3"
    else
        icon="error"
    fi    
    spacefm -g --title "$title" --window-icon $icon \
        --label "\n$1" --button ok  2> /dev/null > /dev/null &
}

killgroup()
{
    pid="$1"
    if (( pid == 0 )); then
        return;
    fi
    if (( verbose )); then
        echo ">>> pkill -P $pid" > "$viewpipe"
        pkill -P $pid 2>&1 > "$viewpipe"
        echo ">>> kill $pid" > "$viewpipe"
        kill $pid 2>&1 > "$viewpipe"
    else
        pkill -P $pid 2>/dev/null
        kill $pid 2>/dev/null
    fi
}

getmediafree()
{
    case "$1" in
        CD-R | CD+R | CD-RW | CD+RW )
            media_free=$cdlimit
            ;;
        DVD-R | DVD+R | DVD-RW | DVD+RW )
            media_free=$dvdlimit
            ;;
        DVD-R/DL | DVD+R/DL )
            media_free=$duallimit
            ;;
        BD-R | BD-RE )
            media_free=$bdrlimit
            ;;
        BD-R/DL | BD-RE/DL )
            media_free=$bdrdllimit
            ;;
        * )
            media_free=0
            ;;
    esac
}

dispsize()
{
    if [ "$media_type" = "" ]; then
        getmediafree "$burn_type"
        (( media_free = media_free * 2048 ))
        (( media_mfree = media_free / 1024 / 1024 ))
    fi
    if (( media_free )); then
        (( percent = bytes * 100 / media_free ))
    else
        percent=100
    fi
    (( mbytes = bytes / 1024 / 1024 ))
    dispsize="$mbytes M"
    msg="$percent %  ( $dispsize / $media_mfree M )"
    if [ "$msg_last" != "$msg" ]; then
        if [ "$media_type" = "" ]; then
            type="$burn_type"
        else
            type="disc"
        fi
        if (( bytes > media_free )); then
            (( exceed = ( bytes - media_free ) / 1024 / 1024 ))
            msg2="exceeds $type by $exceed M"
            remain="-$exceed M"
        else
            (( exceed = ( media_free - bytes ) / 1024 / 1024 ))
            msg2="$exceed M remaining on $type"
            remain="$exceed M"
        fi
        if (( burn_job == 0 )) && [ "$showsize_first" = "" ]; then
            echo -e "\nIn SpaceFM, add content to the Burn Dir using Copy and Edit|Paste Link, or drag and drop while holding Ctrl+Shift.\n" > "$viewpipe"
            showsize_first=x
        fi
        echo "set progress1 $msg" > "$cmdpipe"
        echo "$msg  $msg2" > "$viewpipe"
        settask total "$dispsize / $media_mfree M"
        settask progress "$percent"
        settask curremain "$remain"
        settask avgremain "$remain"
        settask curspeed
        settask avgspeed
        msg_last="$msg"
    fi
}

showcopysize()
{
    if [ "$burn_path" != "$burn_last_path" ]; then
        burn_last_path="$burn_path"
        msg_last=""
        settask from "$burn_path"
        if [ -b "$burn_path" ]; then
            echo "--- Copy Disc source changed to $burn_path" > "$viewpipe"
            image_bytes=`udevil info "$burn_path" | grep -m 1 "^  size:" | sed 's/.*: *\(.*\)/\1/'`
            settask item "Copy Disc $burn_path"
            echo "$burn_path" > "$copydiscfile"
        else
            image_bytes=0
            echo "*** Invalid Copy Disc $burn_path" > "$viewpipe"
            settask item "(invalid - $burn_path)"
        fi
    fi
    (( bytes = image_bytes ))
    if [ "$burn_path" != "$burner" ]; then
        dispsize
    else
        (( mbytes = bytes / 1024 / 1024 ))
        dispsize="$mbytes M"
        msg="Copy Disc: $dispsize"
        if [ "$msg_last" != "$msg" ]; then
            echo "set progress1 100" > "$cmdpipe"
            echo "set progress1 $msg" > "$cmdpipe"
            echo "$msg" > "$viewpipe"
            settask total "$dispsize"
            settask progress 100
            settask curremain ""
            settask avgremain ""
            msg_last="$msg"
        fi
    fi
}

showimagesize()
{
    if [ "$burn_path" != "$burn_last_path" ]; then
        burn_last_path="$burn_path"
        msg_last=""
        settask from
        if [ -f "$burn_path" ]; then
            echo "--- Burn Image changed to $burn_path" > "$viewpipe"
            image_bytes=`stat -c %s "$burn_path"`
            settask item "Burn Image $burn_path"
            echo "$(dirname "$burn_path")" > "$imagepathfile"
            if [ "$isoinfo" = "" ]; then
                echo -e "\n*** Please install isoinfo for more detailed info\n" > "$viewpipe"
            else
                msg=`$isoinfo -d -i "$burn_path" 2>&1`
                err=$?
                if (( verbose )) || [ $err -ne 0 ]; then
                    echo "================================================" > "$viewpipe"
                    echo "$msg" > "$viewpipe"
                    if [ $err -ne 0 ]; then
                        echo -e "\n*** WARNING invalid image contents ?" > "$viewpipe"
                    fi
                    echo "================================================" > "$viewpipe"
                fi
            fi
        else
            image_bytes=0
            echo "*** Invalid Burn Image $burn_path" > "$viewpipe"
            settask item "(invalid - $burn_path)"
        fi
    fi
    (( bytes = image_bytes ))
    dispsize
}

showdirsize()
{
    if [ -d "$burn_path" ]; then
        bytes=`du -sbL "$burn_path" 2>/dev/null`
        if [ $? -ne 0 ]; then
            msg=`du -sbL "$burn_path" 2>&1 | grep ":"`
            if [ "$msg" != "$du_msg_last" ] || \
                                    [ "$burn_path" != "$burn_last_path" ]; then
                du_msg_last="$msg"
            else
                msg=""
            fi
        else
            msg=""
        fi
        bytes="${bytes%%[[:blank:]]*}"
        (( mbytes = bytes / 1024 / 1024 ))
        if [ "$burn_path" != "$burn_last_path" ]; then
            echo "--- Burn Dir changed to $burn_path" > "$viewpipe"
            settask from "$burn_path"
            settask item "Burn Dir - Adding Content"
            burn_last_path="$burn_path"
            msg_last=""
        fi
        if [ "$msg" != "" ]; then
            echo "$msg" > "$viewpipe"
        fi
    else
        bytes=0
        if [ "$burn_path" != "$burn_last_path" ]; then
            echo -e "*** Invalid Burn Dir $burn_path" > "$viewpipe"
            settask from "(invalid - $burn_path)"
            settask item "Burn Dir - invalid"
            burn_last_path="$burn_path"
            msg_last=""
        fi
    fi
    dispsize
}

savespeed()
{
    # save selected speed of burn type
    if [ "$1" = "" ]; then
        return;
    fi
    safetype="$1"
    safetype="${safetype//\//-}"
    speedfile="$fm_cmd_data/config/speed-$safetype"
    if [ "$burn_speed" = "" ] || [ "$burn_speed" = "Max" ]; then
        rm -f "$speedfile"
    else
        echo "$burn_speed" > "$speedfile"
    fi
}

setspeed()
{
    # restore selected speed of burn type
    safetype="$burn_type"
    safetype="${safetype//\//-}"
    speedfile="$fm_cmd_data/config/speed-$safetype"
    speed="$(head -n 1 "$speedfile" 2> /dev/null)"
    if [ "$speed" = "" ]; then
        speed="Max"
    fi
    if [ "$burn_speed" != "$speed" ]; then
        echo "set combo2 $speed" > "$cmdpipe"
        echo "--- Speed changed to $speed" > "$viewpipe"
    fi
}

runalarm()
{
    alarm_cmd="`head -n 1 "$alarmcmdfile" 2>/dev/null`"
    if [ "$alarm_cmd" != "" ]; then
        if (( verbose )); then
            echo ">>> $alarm_cmd &" > "$viewpipe"
        fi
        eval $alarm_cmd &
    fi
}

setstate()
{
    if [ "$1" != "" ]; then
        state="$1"
    fi
    if [ $state = BUILD ]; then
        en_save=1
        if [ $burn_job -eq 0 ]; then
            en_dir=1
            burn_last_path=
        else
            en_dir=0
            if [ $burn_job -eq 1 ]; then
                en_save=0
            else
                burn_last_path=
            fi
        fi
        msg_last=
        echo "enable vbox1 1" > "$cmdpipe"
        echo "enable button2 1" > "$cmdpipe"
        echo "enable button5 1" > "$cmdpipe"
        echo "enable label3 $en_dir" > "$cmdpipe"
        echo "enable input2 $en_dir" > "$cmdpipe"
        echo "enable check1 $en_dir" > "$cmdpipe"
        echo "enable check3 $en_save" > "$cmdpipe"
        spacefm -s remove-event evt_pnl_sel "$selhandler" 2>/dev/null
        spacefm -s replace-event evt_pnl_sel "$selhandler"
        spacefm -s set --window $fm_my_window statusbar_text \
                            "Select files/folders/links to show their deep size"
    else
        echo "enable vbox1 0" > "$cmdpipe"
        echo "enable button2 0" > "$cmdpipe"
        echo "enable button5 0" > "$cmdpipe"
        spacefm -s remove-event evt_pnl_sel "$selhandler" 2>/dev/null
        ( for p in {1..4}; do for t in {1..20}; do spacefm -s set --window \
          "$fm_my_window" --panel $p --tab $t statusbar_text 2>/dev/null; \
          done; done ) &
    fi
}

burnready()
{
    burner="`head -n 1 "$burnerfile" 2>/dev/null`"
    if [ ! -b "$burner" ]; then
        echo "*** Invalid burner drive $burner - please configure a valid burner" > "$viewpipe"
        return 1
    fi
    info="`ps -Af | grep -v grep | grep "/burn.sh .* --burniso $burner"`"
    if [ "$info" != "" ]; then
        echo "*** Burner drive $burner appears to be in use (burn.sh is running)" > "$viewpipe"
        return 1
    fi
    
    unmountburner
    echo -e "\n--- Estimating filesystem size..." > "$viewpipe"
    echo "set progress1 0" > "$cmdpipe" &
    settask item "Preparing to burn"
    settask total
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    settask curspeed
    settask avgspeed
    if (( burn_job == 0 )); then
        # Burn Dir
        echo "$burn_verify" > "$verifyfile"
        echo "$burn_checksums" > "$checksumsfile"
        if [ ! -d "$burn_path" ]; then
            echo "*** Invalid Burn Dir" > "$viewpipe"
            return 1
        fi
        estimate="$(printsize "$burn_path")"
        if [ $? -ne 0 ]; then
            echo "*** Error running $mkisofs for filesystem size" > "$viewpipe"
            return 1
        fi
        (( estimate = estimate * 2048 ))
        create_iso_est=$estimate
    elif (( burn_job == 1 )); then
        # Burn Image
        if [ ! -s "$burn_path" ]; then
            echo "*** Invalid Burn Image" > "$viewpipe"
            return 1
        fi
        estimate=`stat -c %s "$burn_path"`
    else  # (( burn_job == 2 ))
        # Copy Disc
        if [ ! -b "$burn_path" ]; then
            echo "*** Invalid Copy Disc source - $burn_path is not a block device" > "$viewpipe"
            return 1
        fi
        info="`udevil info "$burn_path"`"
        estimate="`echo "$info" | grep -m 1 "^  size:" | sed 's/.*: *\(.*\)/\1/'`"
        create_iso_est=$estimate
        has_media="`echo "$info" | grep "^  has media:" | sed 's/.*: *\(.*\)/\1/'`"
        is_blank="`echo "$info" | grep "^    blank:" | sed 's/.*: *\(.*\)/\1/'`"
        if (( estimate * has_media == 0 )) || (( is_blank == 1 )); then
            eval "`spacefm -g --window-icon gtk-dialog-warning --title "Invalid Copy Disc Media" \
                    --label "\nThe Copy Disc source $burn_path does not seem to contain valid non-empty media to read.  Do you want to attempt to copy this disc anyway?" \
                    --button Continue:gtk-yes \
                    --button cancel`"
            if [ "$dialog_pressed" != "button1" ]; then
                echo "*** Burn cancelled" > "$viewpipe"
                return 1
            fi
        fi
    fi
    echo -e "--- Checking media..." > "$viewpipe"
    if (( burn_job == 2 )); then
        return 0
    fi
    info="`udevil info "$burner" 2> "$viewpipe"`"
    blocksize="`echo "$info" | grep -m 1 "^  block size:" | sed 's/.*: *\(.*\)/\1/'`"
    if (( blocksize == 0 )); then
        blocksize=$default_blocksize
    fi
    if (( blocksize == 0 )); then
        blocksize=2048
    fi
    info="`$cdrecord dev="$burner" -media-info 2> /dev/null`"
    err=$?
    media_type_est="`echo "$info" | grep -m 1 "^Mounted media type:" | sed 's/Mounted media type: *\([A-Za-z\+\/-]*\) *.*/\1/'`"
    media_status_est="`echo "$info" | grep -m 1 "^disk status:" | sed 's/disk status: *\(.*\)/\1/'`"
    media_free_est="`echo "$info" | grep -m 1 "^Remaining writable size:" | sed 's/Remaining writable size: *\(.*\)/\1/'`"
    if [ "$media_status_est" = "empty" ] && [ "$media_free_est" = "" ]; then
        # No "Remaining writable size" so try to get free sectors
        media_free_est="`echo "$info" | grep -m 1 " *1 *1 *Blank *0 *[0-9]* " | sed 's/ *1 *1 *Blank *0 *\([0-9]*\) .*/\1/'`"
    fi
    if [ "$media_type_est" != "${media_type_est#BD}" ] && \
                    [ "$media_type_est" = "${media_type_est%DL}" ] && \
                    (( media_free_est > bdrlimit + 100000 )); then
        # help detection of DL
        media_type_est="$media_type_est/DL"
    fi
    (( media_free_est = media_free_est * blocksize ))
    if [ $err -ne 0 ] || [ "$media_status_est" = "" ]; then
        # no media info
        eval "`spacefm -g --window-icon gtk-dialog-warning --title "Media Info Error" \
                --label "\nUnable to get info about the media in $burner using $cdrecord.  Do you want to attempt this burn anyway?" \
                --button Continue:gtk-yes \
                --button cancel`"
        if [ "$dialog_pressed" != "button1" ]; then
            echo "*** Burn cancelled" > "$viewpipe"
            return 1
        fi
    else
        if [ "$media_status_est" != "empty" ]; then
            # media not blank
            if [ "$media_type_est" = "${media_type_est/RW/}" ] && \
                        [ "$media_type_est" == "${media_type_est/RE/}" ]; then
                msg=", and the media doesn't look rewritable"
            else
                msg=""
            fi
            eval "`spacefm -g --window-icon gtk-dialog-warning --title "Media Not Blank" \
                    --window-size 600 \
                    --label "~\nThe $media_type_est media in $burner is not blank$msg.\n\n<b>This plugin does not burn multisession discs.</b>\n\nDo you want to attempt to <b>overwrite this disc?</b>" \
                    --button Over_write:gtk-yes \
                    --button cancel`"
            if [ "$dialog_pressed" != "button1" ]; then
                echo "*** Burn cancelled" > "$viewpipe"
                return 1
            fi
            # normal size
            case "$media_type_est" in
                CD-R | CD+R | CD-RW | CD+RW )
                    media_free_est=$cdlimit
                    ;;
                DVD-R | DVD+R | DVD-RW | DVD+RW )
                    media_free_est=$dvdlimit
                    ;;
                DVD-R/DL | DVD+R/DL )
                    media_free_est=$duallimit
                    ;;
                BD-R | BD-RE )
                    media_free_est=$bdrlimit
                    ;;
                BD-R/DL | BD-RE/DL )
                    media_free_est=$bdrdllimit
                    ;;
                * )
                    media_free_est=-1
                    ;;
            esac
            (( media_free_est = media_free_est * 2048 ))
        fi
        if (( media_free_est < estimate )) && (( media_free_est != -1 )); then
            if (( burn_job == 0 )); then

                (( diff = ( estimate - media_free_est ) / 1024 / 1024 + 1 ))
                msg="With filesystem overhead included, you need to remove approximately $diff M from the Burn Dir.\n\nOr to attempt this burn as is, click Continue."
            else
                msg="Do you want to attempt this burn anyway?"
            fi
            eval "`spacefm -g --window-icon gtk-dialog-warning --title "Insufficient Space" \
                    --window-size 600 \
                    --label "~\nThe $media_type_est media in $burner has <b>insufficient space</b>.\n\n$msg" \
                    --button Continue:gtk-yes \
                    --button cancel`"
            if [ "$dialog_pressed" != "button1" ]; then
                echo "*** Burn cancelled" > "$viewpipe"
                return 1
            fi
        fi
    fi
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
            settask total
            settask progress 0
            settask progress ""
            settask curremain
            settask avgremain
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
        echo "*** Unable to determine mount point" > "$viewpipe"
        return 1
    fi
}

reloadtray()
{
    echo "--- Reloading $burner..." > "$viewpipe"
    settask item "Reloading tray"
    settask total
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    if (( verbose )); then
        echo ">>> eject -r $burner" > "$viewpipe"
    fi
	eject -r $burner
	sleep 2
    if (( verbose )); then
        echo ">>> eject -t $burner" > "$viewpipe"
    fi
	eject -t $burner
    sleep 2
}

unmountburner()
{
    is_mounted="`udevil info "$burner" 2> "$viewpipe" | grep "^  is mounted:" | \
                                                        sed 's/.*: *\(.*\)/\1/'`"
    if (( is_mounted )); then
        echo "--- Unmounting $burner..." > "$viewpipe"
        settask item "Unmounting $burner";
        settask total
        settask progress 0
        settask progress ""
        settask curremain
        settask avgremain
        if (( verbose )); then
            echo ">>> udevil --quiet umount \"$burner\"" > "$viewpipe"
        fi
        udevil --quiet umount "$burner" > "$viewpipe" 2> "$viewpipe"
    fi
}

startiso()
{
    if (( burn_saveimage )) && [ "$burn_saveimage_path" != "" ]; then
        createiso_path="$burn_saveimage_path"
    else
        burn_saveimage=0
        largetmpdir="`head -n 1 "$largetmpdirfile" 2>/dev/null`"
        if [ ! -d "$largetmpdir" ]; then
            largetmpdir="$smalltmp"
        fi
        # reuse tmpiso_path unless largetmpdir changed
        len="${#largetmpdir}"
        if [ "${tmpiso_path:0:len}/" != "$largetmpdir/" ]; then
            if [ "$tmpiso_path" != "" ]; then
                if (( verbose )); then
                    echo ">>> rm -f \"$tmpiso_path\" &" > "$viewpipe"
                fi
                rm -f "$tmpiso_path" &
            fi
            tmpiso_path=
            while [ "$tmpiso_path" = "" ] || [ -e "$tmpiso_path" ]; do
                fm_randhex4
                tmpiso_path="$largetmpdir/burndisc-$fm_randhex.iso"
            done
        fi
        createiso_path="$tmpiso_path"
    fi
    if (( verbose )); then
        verboseopt="--verbose"
    else
        verboseopt=""
    fi
    settask item "Creating image"
    settask to "$burner"
    settask from "$burn_path"
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    echo "set progress1 0" > "$cmdpipe" &
    if [ $burn_job -eq 0 ]; then
        isojob="--createiso"
    else
        isojob="--copyiso"
    fi
    # reuse prior iso?
    size=`stat -c %s "$createiso_path" 2>/dev/null`
    if [ -e "$createiso_path" ] && (( size == create_iso_est )); then
        eval "`spacefm -g --title "Reuse Image ?" \
                    --label "\nAn image with this filesystem size was already created.  Reuse this image?\n\n$createiso_path" \
                    --button "_Create New" --button "_Reuse"`"
        if [ "$dialog_pressed" != "button1" ]; then
            echo "--- Reusing prior image $createiso_path" > "$viewpipe"
            createiso_pid=-100
            ( sleep 1; echo "isook" > "$respipe" ) &
            return
        fi
    fi
    # start create/replace iso
    bash "$fm_cmd_dir/burn.sh" $verboseopt $isojob \
                                "$burn_path" "$createiso_path" "$burn_type" "$burn_label" &
    createiso_pid=$!
}

startburn()
{
    echo "set progress1  " > "$cmdpipe"
    settask item "Burn Starting"
    settask total
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    if (( burn_job == 2 )); then
        # Copy Disc
        # if src and dest drive are same, get user to change disc
        if [ "$burner" = "$burn_path" ]; then
            if (( verbose )); then
                echo ">>> eject -r $burner &" > "$viewpipe"
            fi
            echo "--- Please insert a blank or rewritable disc in $burner..." > "$viewpipe"
            eject -r $burner &
            runalarm
            while true; do
                eval "`spacefm -g --title "Insert Media" \
                            --label "\nPlease insert a blank or rewritable disc in $burner." \
                            --button cancel --button ok`"
                if [ "$dialog_pressed" != "button2" ]; then
                    echo "*** Burn canceled" > "$viewpipe"
                    setstate BUILD
                    burn_pid=0
                    return
                fi
                has_media="`udevil info "$burner" | grep "^  has media:" | sed 's/.*: *\(.*\)/\1/'`"
                if (( has_media == 1 )); then
                    break
                fi
            done
        fi
        burn_job=1
        burn_path="$createiso_path"
        if ! burnready ; then
            setstate BUILD
            burn_pid=0
            return
        fi
    fi
    if [ ! -e "$createiso_path" ]; then
        echo "*** Burn error - iso file is missing" > "$viewpipe"
        setstate BUILD
        burn_pid=0
        return
    fi
    settask from "$burn_path"
    if (( verbose )); then
        verboseopt="--verbose"
    else
        verboseopt=""
    fi
    if [ "$media_type" = "CD-RW" ] || [ "$media_type" = "CD+RW" ]; then
        blank="1"
    else
        blank=""
    fi
    if [ "$burn_speed" != "" ] && [ "$burn_speed" != "Max" ]; then
        speed="${burn_speed%x}"
    else
        speed=""
    fi
    burntime=`date +%s`
    bash "$fm_cmd_dir/burn.sh" $verboseopt --burniso "$burner" \
                                "$createiso_path" "$burn_type" "$speed" "$blank" &
    burn_pid=$!
}

startsnapshot()
{
    echo "--- Writing Snapshot..." > "$viewpipe"
    echo "set progress1  " > "$cmdpipe"
    settask item "Writing Snapshot"
    settask total
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    settask curspeed
    settask avgspeed
    old_path="$(pwd)"
    cd "$point"
    if [ $? -ne 0 ] || (( burn_snapshot != 1 )) || [ "$burn_snapshot_path" = "" ] || \
                                [ ! -d "$point" ]; then
        echo "*** Failed to write snapshot" > "$viewpipe"        
        return 1
    fi

    if [ -e ".checksum.md5.gz" ]; then
        media_date=`stat -c %y ".checksum.md5.gz"`
        media_date="${media_date%% *}"
    else
        media_date="$(date "+%Y-%m-%d")"
    fi
    echo "SNAPSHOT:  $vollabel" > "$burn_snapshot_path"
    echo "           $burn_type  $media_date" >> "$burn_snapshot_path"
    echo >> "$burn_snapshot_path"
    /bin/ls -1RshpAv >> "$burn_snapshot_path" 2> "$viewpipe"
    if (( verbose )); then
        echo "---------------------------------------" > "$viewpipe"
        echo "SNAPSHOT:  $vollabel" > "$viewpipe"
        echo "           $burn_type  $media_date" > "$viewpipe"
        echo > "$viewpipe"
        /bin/ls -1RshpAv | head -n 20 > "$viewpipe"
        echo "..." > "$viewpipe"
        echo "---------------------------------------" > "$viewpipe"
    fi
    cd "$old_path"
}

startverify()
{
    echo "--- $burn_verify..." > "$viewpipe"
    echo "set progress1  " > "$cmdpipe"
    settask item "$burn_verify"
    settask total
    settask progress 0
    settask progress ""
    settask curremain
    settask avgremain
    settask curspeed
    settask avgspeed
    if (( verbose )); then
        verboseopt="--verbose"
    else
        verboseopt=""
    fi
    bash "$fm_cmd_dir/verify.sh" $verboseopt "$burn_verify" "$burner" \
                                         "$burn_path" "$createiso_path" "$point" &
    verify_pid=$!
}


# events
spacefm -s add-event evt_device "echo %f > '$respipe'"
selhandler="if [ '%w' != '$fm_my_window' ]; then exit 1; fi; source '$fm_cmd_dir/status.sh' %w %p %t &"

# default burn path and job
jobs=( "Burn Dir:" "Burn Image:" "Copy Disc:" )
init_path="$fm_file"
if [ -f "$init_path" ]; then
    mtype="`file -L --mime-type "$init_path"`"
    mtype="${mtype##*: }"
    for ext in .iso .ISO .raw .RAW .img .IMG; do
        ext="${init_path/%$ext/.XXX}"
    done
    if [ "$ext" != "$init_path" ] || [ "$mtype" = "application/x-cd-image" ] || \
                            [ "$mtype" = "application/x-iso9660-image" ]; then
        init_job=1
    else
        init_path=""
    fi
elif [ -b "$init_path" ]; then
    init_job=2
else
    init_job=0
    if [ ! -d "$init_path" ]; then
        init_path=""
    fi
fi
if [ "$init_path" = "" ]; then
    init_job=0
    init_path="$(pwd)"
fi
verify=( "Don't Verify" "Verify Checksums" "Compare To Image" "Compare To Dir" )
burn_verify="`head -n 1 "$verifyfile" 2> /dev/null`"
if [ "$burn_verify" = "" ]; then
    burn_verify="Verify Checksums"
fi
if (( init_job != 0 )) && [ "$burn_verify" != "Don't Verify" ]; then
    burn_verify="Compare To Image"
fi
    
# show dialog
spacefm -g --title "Burn Disc" --window-size "@$winsizefile" \
    --vbox --compact \
        --hbox --compact \
            --drop "${jobs[@]}" -- +$init_job \
                   bash -c "echo job > '$respipe'" \
            --input "$init_path" press freebutton1 \
            --free-button :gtk-open bash -c "echo browse > '$respipe'" \
        --close-box \
        --hbox --compact \
            --label "Type:" \
            --combo "@$typelist" "unknown" bash -c "echo type > '$respipe'" \
            --label "Speed:" \
            --combo "@$speedlist" +0 noop \
            --label "Label:" \
            --input "" noop \
        --close-box \
        --hbox --compact \
            --check "Checksums" $checksums_init \
                    bash -c "echo checksums > '$respipe'" \
            --check "Snapshot" 0 bash -c "echo snapshot > '$respipe'" \
            --check "Save Image" 0 bash -c "echo saveimage > '$respipe'" \
            --drop "${verify[@]}" -- "$burn_verify" \
                    bash -c "echo verify > '$respipe'" \
        --close-box \
    --close-box \
    --hsep \
    --progress "" \
    --viewer --scroll "$viewpipe" "$tmplogfile" \
    --button _Help:gtk-help bash -c "echo help > '$respipe'" \
    --button C_onfigure:gtk-preferences bash "$fm_cmd_dir/configure.sh" \
    --button "_Save Log:gtk-save" bash "$fm_cmd_dir/savelog.sh" \
    --button cancel bash -c "echo cancel > '$respipe'" \
    --button _Burn:gtk-cdrom bash -c "echo burn > '$respipe'" \
    --window-close press button4 \
    --command "$cmdpipe" focus input1 > /dev/null &

dlgpid=$!

if (( verbose )); then
    echo "cdrecord=$cdrecord" > "$viewpipe"
    echo "mkisofs=$mkisofs" > "$viewpipe"
fi

# start
# This loop makes the dialog a state machine, changing its state through
# different parts of the burn process.
state=BUILD
trap "echo SIGTERM ignored" SIGTERM
trap "echo SIGQUIT ignored" SIGQUIT
trap "echo SIGINT ignored" SIGINT
trap "echo SIGHUP ignored" SIGHUP
( sleep .75; settask item "Burn Dir - Adding Content"; \
             settask to "$burner"; \
             settask from ""; \
             settask progress 0;
             settask popup_handler "echo focus > '$cmdpipe'" ) &
burn_job=$init_job
setstate
getdisc "$burner"
if [ "$media_label" = "" ]; then
    if [ $burn_job -eq 0 ]; then
        label="`basename "$init_path"`"
        echo "set input2 $label" > "$cmdpipe"
    fi
else
    echo "set input2 $media_label" > "$cmdpipe"
fi
while [ -p "$respipe" ] && [ -p "$cmdpipe" ] && ps -p $dlgpid 2>&1 >/dev/null; do
	read -t .7 <> "$respipe"
    if [ $? -eq 0 ]; then
        #if (( verbose )); then
        #    echo "REPLY=$REPLY" > "$viewpipe"
        #fi
        case "$REPLY" in
            help )
                fm_edit "$fm_cmd_dir/README" &
                ;;
            checksums )
                if [ $state = BUILD ]; then
                    getsrc
                    if (( burn_checksums == 0 )); then
                        echo -e '\n*** NOTE:  Adding checksums takes a few extra minutes, but allows you to later verify a disc even after the original files are gone.  To enable this feature select Checksums.\n' > "$viewpipe"
                        if [ "$burn_verify" = "Verify Checksums" ]; then
                            echo "select drop2 Compare To Image" > "$cmdpipe"
                        fi
                    else
                        if [ "$burn_verify" != "Don't Verify" ]; then
                            echo "select drop2 Verify Checksums" > "$cmdpipe"
                        fi                    
                    fi
                fi
                ;;
            verify )
                if [ $state = BUILD ]; then
                    getsrc
                    if (( burn_job != 0 )); then
                        if [ "$burn_verify" = "Verify Checksums" ] || \
                                        [ "$burn_verify" = "Compare To Dir" ]; then
                            echo "select drop2 Compare To Image" > "$cmdpipe"
                        fi
                    elif (( burn_checksums == 0 )) && \
                                    [ "$burn_verify" = "Verify Checksums" ]; then
                        echo "set check1 1" > "$cmdpipe"
                        #echo "select drop2 Compare To Image" > "$cmdpipe"
                    fi
                fi
                ;;
            snapshot | saveimage )
                if [ $state = BUILD ]; then
                    getsrc
                    if [ "$REPLY" = "snapshot" ]; then
                        if (( burn_snapshot != 1 )); then
                            continue
                        fi
                        title="Save Snapshot As"
                        path="`head -n 1 "$snapshotpathfile" 2> /dev/null`"
                        if [ "$path" = "" ]; then
                            eval path="~/burndisc-snapshots"
                            mkdir -p $path
                        fi
                        if [ "$burn_snapshot_path" != "" ]; then
                            path="$burn_snapshot_path"
                        elif [ "$burn_label" != "" ] && (( burn_job == 0 )); then
                            path="$path/$burn_label"
                        else
                            path="$path/snapshot" ########### bugfix only
                        fi
                        check=check2
                        savefile="$snapshotpathfile"
                    else
                        if (( burn_saveimage != 1 )); then
                            continue
                        fi
                        title="Save Image As"
                        path="`head -n 1 "$saveimagepathfile" 2> /dev/null`"
                        if [ "$path" = "" ]; then
                            path="$(pwd)"
                        fi
                        if [ "$burn_saveimage_path" != "" ]; then
                            path="$burn_saveimage_path"
                        elif [ "$burn_label" != "" ] && (( burn_job == 0 )); then
                            path="$path/$burn_label.iso"
                        else
                            path="$path/image.iso"
                        fi
                        check=check3
                        savefile="$saveimagepathfile"
                    fi
                    while (( 1 )); do
                        eval "`spacefm -g --window-size "@$choosersizefile" \
                                   --title "$title" \
                                   --chooser --save "$path" \
                                   --button cancel \
                                   --button ok`"
                        if [ "$dialog_pressed" = "button2" ] && \
                                                [ "$dialog_chooser1" != "" ]; then
                            path="$dialog_chooser1"
                            if [ -e "$path" ]; then
                                eval "`spacefm -g --title "File Exists" \
                                    --label "\nFile '$path' already exists.\n\nOverwrite?" \
                                    --button yes \
                                    --button no`"
                                if [ "$dialog_pressed" = "button1" ]; then
                                    break
                                fi
                            else
                                break
                            fi
                        else
                            echo "set $check 0" > "$cmdpipe"
                            path=""
                            break
                        fi
                    done
                    if [ "$path" != "" ]; then
                        echo "$(dirname "$path")" > "$savefile"
                    fi
                    if [ "$REPLY" = "snapshot" ]; then
                        burn_snapshot_path="$path"
                    else
                        burn_saveimage_path="$path"
                    fi
                fi
                ;;
            job | browse )
                if [ $state = BUILD ]; then
                    if (( burn_job == 0 )); then
                        if [ "$burn_verify" != "" ]; then
                            echo "$burn_verify" > "$verifyfile"
                        fi
                    fi
                    getsrc
                    if [ "$REPLY" = job ]; then
                        setstate
                        burn_path_last=""
                        msg_last=""
                    fi
                    if (( burn_job == 0 )); then
                        diropt="--dir"
                        path="$burn_path"
                        title="Choose Directory To Burn"
                        verify="`head -n 1 "$verifyfile" 2> /dev/null`"
                        if [ "$verify" = "" ]; then
                            verify="Verify Checksums"
                        fi
                        echo "select drop2 $verify" > "$cmdpipe"
                    elif (( burn_job == 1 )); then
                        diropt=""
                        path="`head -n 1 "$imagepathfile" 2> /dev/null`"
                        if [ "$path" = "" ]; then
                            path="$burn_path"
                        fi
                        title="Choose Image To Burn"
                        if [ "$burn_verify" != "Don't Verify" ]; then
                            echo "select drop2 Compare To Image" > "$cmdpipe"
                        fi
                    elif (( burn_job == 2 )); then
                        path=`head -n 1 "$copydiscfile" 2> /dev/null`
                        if [ "$path" = "" ]; then
                            path="$burner"
                        fi
                        echo "set input1 $path" > "$cmdpipe"
                        if [ "$burn_verify" != "Don't Verify" ]; then
                            echo "select drop2 Compare To Image" > "$cmdpipe"
                        fi
                        continue
                        #diropt=""
                        #if [ "${burn_path:0:5}" = "/dev/" ]; then
                        #    path="$burn_path"
                        #else
                        #    path="/dev"
                        #fi
                        #title="Choose Drive To Copy"
                    fi
                    if [ "${path:0:5}" = "/dev/" ]; then
                        path=`pwd`
                    fi
                    spacefm -g --window-size "@$choosersizefile" \
                               --title "$title" \
                               --chooser $diropt "$path" \
                               --button cancel \
                               --button ok \
                                 bash -c "[[ -p '$cmdpipe' ]] && \
                                          echo \"set input1 %chooser1\" \
                                          > '$cmdpipe'" -- close \
                            > /dev/null &
                fi
                ;;
            burn )
                if [ $state = BUILD ]; then
                    state=PREBURN
                    getsrc
                    savespeed "$burn_type"
                    setstate
                    if ! burnready; then
                        setstate BUILD
                    elif (( burn_job == 0 && burn_checksums == 1 )); then
                        echo "--- Generating checksums..." > "$viewpipe"
                        echo "set progress1 0" > "$cmdpipe" &
                        settask item "Burn Dir - Adding Checksums"; \
                        settask to "$burner"; \
                        settask from "$burn_path"; \
                        settask progress 0;
                        settask progress ""
                        settask curremain
                        settask avgremain
                        if (( verbose )); then
                            verbopt="--verbose"
                        else
                            verbopt=""
                        fi
                        bash "$fm_cmd_dir/checksums.sh" $verbopt "$burn_path" &
                        checksums_pid=$!
                    elif (( burn_job == 0 )); then
                        startiso
                    elif (( burn_job == 1 )); then
                        createiso_path="$burn_path"
                        setstate BURN
                        echo "set progress1 0" > "$cmdpipe" &
                        startburn                        
                    elif (( burn_job == 2 )); then
                        startiso
                    else
                        setstate BUILD
                    fi
                fi
                ;;
            checksumsfail )
                if [ $state = PREBURN ]; then
                    checksums_pid=0
                    echo "*** Burn cancelled" > "$viewpipe"
                    runalarm
                    showmsg "Checksum generation failed."
                    setstate BUILD
                fi
                ;;
            checksumsok )
                if [ $state = PREBURN ]; then
                    checksums_pid=0
                    if (( burn_job == 0 )); then
                        echo "set progress1 0" > "$cmdpipe" &
                        startiso
                    else
                        echo "DONE OK" > "$viewpipe"
                        setstate BUILD
                    fi
                fi
                ;;
            isofail )
                if [ $state = PREBURN ]; then
                    createiso_pid=0
                    echo "*** Burn cancelled" > "$viewpipe"
                    runalarm
                    showmsg "Image creation failed."
                    setstate BUILD
                fi
                ;;
            isook )
                if [ $state = PREBURN ] && (( createiso_pid )); then
                    createiso_pid=0
                    setstate BURN
                    echo "set progress1 0" > "$cmdpipe" &
                    startburn
                fi
                ;;
            burnfail )
                if [ $state = BURN ]; then
                    burn_pid=0
                    echo "*** BURN FAILED !" > "$viewpipe"
                    showmsg "Burn failed."
                    now=`date +%s`
                    if (( now - burntime > 5 )); then
                        runalarm
                    fi
                    setstate BUILD
                fi
                ;;
            burnok )
                if [ $state = BURN ]; then
                    burn_pid=0
                    echo "--- BURN OK" > "$viewpipe"
                    echo "set progress1 0" > "$cmdpipe"
                    echo "set progress1" > "$cmdpipe"
                    settask total
                    settask progress 0
                    settask progress ""
                    settask curremain
                    settask avgremain
                    reloadtray
                    if (( burn_snapshot )) || [ "$burn_verify" != "Don't Verify" ]; then
                        if ! mountburner; then
                            showmsg "Verification failed - unable to mount."
                            runalarm
                            setstate BUILD
                        else
                            setstate POSTBURN
                            if (( burn_snapshot )); then
                                startsnapshot
                            fi
                            if [ "$burn_verify" != "Don't Verify" ]; then
                                startverify
                            else
                                runalarm
                                setstate BUILD
                            fi
                        fi
                    else
                        setstate BUILD
                    fi
                fi
                ;;
            stopburn )
                if [ $state = BURN ] && (( burn_pid )); then
                    killgroup $burn_pid
                    burn_pid=0
                    echo "*** Burn cancelled" > "$viewpipe"
                    setstate BUILD
                fi
                ;;
            verifyfail )
                if [ $state = POSTBURN ] && (( verify_pid )); then
                    verify_pid=0
                    echo "*** VERIFY FAILED" > "$viewpipe"
                    showmsg "Verification failed."
                    runalarm
                    setstate BUILD
                fi
                ;;
            verifyok )
                if [ $state = POSTBURN ] && (( verify_pid )); then
                    verify_pid=0
                    echo "--- VERIFY OK" > "$viewpipe"
                    runalarm
                    setstate BUILD
                fi
                ;;
            configure )
                if [ $state = BUILD ]; then
                    burner="`head -n 1 "$burnerfile" 2>/dev/null`"
                    media_last_type=X
                    getdisc "$burner"
                    msg_last=""
                fi
                ;;
            verbose )
                verbose="`head -n 1 "$verbosefile" 2>/dev/null`"
                ;;
            cancel )
                if [ $state = BUILD ]; then
                    echo close > "$cmdpipe"
                    break
                elif [ $state = PREBURN ]; then
                    setstate BUILD
                    msg_last=""
                    echo "*** Burn cancelled" > "$viewpipe"
                    killgroup $checksums_pid
                    checksums_pid=0
                    if (( createiso_pid )); then
                        killgroup $createiso_pid
                        createiso_pid=0
                        #if [ "$createiso_path" != "" ]; then
                        #    if (( verbose )); then
                        #        echo ">>> rm -f \"$createiso_path\" &" > "$viewpipe"
                        #    fi
                        #    rm -f "$createiso_path" &
                        #fi
                    fi
                elif [ $state = BURN ]; then
                    spacefm -g --title "Cancel Burn?" --window-icon gtk-dialog-warning \
                               --label "\nA burn appears to be in progress.  If you stop the burn the disc may be incomplete." \
                               --button "_Stop Burn:gtk-cancel" \
                                        bash -c "echo stopburn > '$respipe'" \
                                        -- close \
                               --button _Continue:gtk-yes \
                            > /dev/null &
                elif [ $state = POSTBURN ]; then
                    setstate BUILD
                    msg_last=""
                    echo "*** Verify cancelled" > "$viewpipe"
                    killgroup $verify_pid
                    verify_pid=0
                fi
                ;;
            * )
                if [ $state = BUILD ]; then
                    burner="`head -n 1 "$burnerfile" 2>/dev/null`"
                    if [ "${REPLY:0:5}" = "/dev/" ] && [ "$REPLY" = "$burner" ]; then
                        # don't getdisc too frequently - on some systems cdrecord -media-info
                        # triggers another udev changed event
                        now=`date +%s`
                        if (( now - getdisc_time > 7 )); then
                            sleep 1
                            getdisc "$burner"
                            msg_last=""
                            if (( burn_job == 2 )); then
                                burn_last_path=""
                            fi
                        fi
                    fi
                fi
                ;;
        esac
    fi
    if [ $state = BUILD ]; then
        getsrc
        if [ "$burn_type" != "$burn_last_type" ]; then
            # Type changed
            echo "--- Type changed to $burn_type" > "$viewpipe"
            savespeed "$burn_last_type"
            setspeed
            burn_last_type="$burn_type"
            msg_last=""
        fi
        if (( burn_job == 0 )); then
            showdirsize
        elif (( burn_job == 1 )); then
            showimagesize
        elif (( burn_job == 2 )); then
            showcopysize
        fi
    elif [ $state = PREBURN ]; then    
        if (( createiso_pid )); then
            if [ -e "$createiso_path" ]; then
                size=`stat -c %s "$createiso_path"`
            else
                size=0
            fi
            (( percent = size * 100 / create_iso_est ))
            if (( percent == 0 )); then
                echo "set progress1 pulse" > "$cmdpipe"
            else
                echo "set progress1 $percent" > "$cmdpipe"
            fi
        fi
    elif [ $state = BURN ]; then
        if (( tick++ > 2 )); then  # don't update every time
            tick=0
            getsrc
            #50 % ( 122 M / 244 M ) (fifo 100%) [buf  99%]  10.8x"
            percent="${burn_progress%% %*}"
            if [ "$percent" != "" ] && (( percent != 0 )); then
                (( percent = percent ))
                total="${burn_progress##*( }"
                total="${total%% )*}"
                speed="${burn_progress##*] }"
                while [ "${speed:0:1}" = " " ]; do
                    speed="${speed:1}"
                done
                extra="${burn_progress##* ) }"
                extra="${extra%%]*}]"
                settask item "Burning $extra"
                settask progress "$percent"
                settask curspeed "$speed"
                settask total "$total"
            fi
        fi
    elif [ $state = POSTBURN ] && (( verify_pid )) && \
                                    [ "$burn_verify" != "Compare To Dir" ]; then
        echo "set progress1 pulse" > "$cmdpipe"
    fi
done


# cleanup
settask popup_handler
spacefm -s remove-event evt_device "echo %f > '$respipe'"
spacefm -s remove-event evt_pnl_sel "$selhandler" 2>/dev/null
( for p in {1..4}; do for t in {1..20}; do spacefm -s set --window \
  "$fm_my_window" --panel $p --tab $t statusbar_text 2>/dev/null; \
  done; done ) &
settask item "Burn Disc - Removing tmp files"
rm -f "$cmdpipe"
rm -f "$viewpipe"
rm -f "$respipe"
rm -f "$savelogfile"
rm -rf "$smalltmp"
if [ "$tmpiso_path" != "" ]; then
    rm -f "$tmpiso_path" &
fi

exit


