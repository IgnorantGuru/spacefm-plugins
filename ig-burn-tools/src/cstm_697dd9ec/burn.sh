#!/bin/bash

# IG Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# burn.sh:  This script contains the commands to create filesystem images
#           and burn them to disc.  Adjust your burn commands or options here.

# NOTE: If you have prefered cdrecord/mkisofs programs, set them in config.sh


# The base command to create a filesystem image:
# ( Note that earlier xorrisofs requires options to be separated  eg NO -fRrJ )
mkisofs_base="$mkisofs -f -R -r -J -joliet-long -iso-level 3"

if [ "$1" = "--verbose" ]; then
    verbose=1
    shift
else
    verbose=0
fi

checkprog()
{
    if [ "$mkisofs" = "" ] || [ "$cdrecord" = "" ]; then
        echo "error: mkisofs or cdrecord not set" > "$viewpipe"
        return 1
    fi
}

printsize()
{
    # print the number of 2K sectors required to burn the dir
    if ! checkprog; then
        exit 1
    fi
    tree="$1"
    if (( verbose )); then
        echo ">>> $mkisofs_base -print-size \"$tree\"" > "$viewpipe"
    fi
    $mkisofs_base -print-size "$tree" 2>/dev/null
    return $?
}

setstatus()
{
    # Parses pacifier lines of cdrecord/cdrskin and updates status
    # Thanks to Thomas Schmitt <scdbackup@gmx.net> for read method
    line=
    bslast=0
    while true; do
        # Progress lines in cdrskin and cdrecord terminate with CR, so need
        # to read one character at a time
        read -n 1 c
        if [ $? -ne 0 ]; then
            break
        fi
        if [ "$c" = $'\r' ] || [ "$c" = "" ]; then
            # CR or LF received
            if (( verbose )) || \
                            [ "$line" != "${line#Writing *time:}" ] || \
                            [ "$line" != "${line#Average write speed}" ] || \
                            [ "$line" != "${line#Min drive buffer fill was}" ] || \
                            [ "$line" != "${line#Fixating}" ] || \
                            [ "$line" != "${line#Starting to write}" ] || \
                            [ "$line" != "${line#Performing }" ] || \
                            [ "$line" != "${line#Blanking }" ] || \
                            [ "$line" != "${line/Total bytes/}" ] || \
                            [ "$line" != "${line/error/}" ] || \
                            [ "$line" != "${line/fifo was /}" ] || \
                            [ "$line" != "${line/fifo had /}" ]; then
                echo "$line" > "$viewpipe"
            fi
            #Track 01:    122 of  244 MB written (fifo 100%) [buf  99%]  10.8x.
            total="${line%% MB written*}"
            total="${total#*: }"
            written="${total%% of *}"
            total="${total##* of }"
            if [ "$written" != "" ] && [ "$total" != "" ]; then
                extra="${line##* written }"
                if [ "$extra" != "$line" ]; then
                    (( total = total ))
                    (( written = written ))
                    (( percent = written * 100 / total ))
                    extra="${extra%.}"
                    percent="$percent % ( $written M / $total M ) $extra"
                    plen=${#percent}
                    if (( plen > 0 && plen < 80 )); then
                        echo "set progress1 $percent" > "$cmdpipe" &
                    else
                        echo "set progress1 pulse" > "$cmdpipe" &
                    fi
                fi
            fi
            line=
            bslast=0
        elif [ "$c" != $'\x08' ]; then    # ignore backspaces
            line="$line$c"
            bslast=0
        elif (( bslast == 0 )); then
            # add linefeed on first backspace of a series
            if (( verbose )); then
                echo "$line" > "$viewpipe"
            fi
            line=
            bslast=1
        fi
    done
}

if [ "$1" = "--createiso" ]; then
    # create an iso file from directory tree
    tree="$2"
    iso="$3"
    type="$4"
    vollabel="$5"
    echo "--- Creating image..." > "$viewpipe"
    if (( verbose )); then
        echo "    as $iso" > "$viewpipe"
    fi
    if ! checkprog; then
        echo "isofail" > "$respipe"
        exit 1
    fi
    #rm -f "$iso"
    if [ "$vollabel" = "" ]; then
        volopt=
    else
        volopt="-V"
    fi
    if (( verbose )); then
        echo ">>> $mkisofs_base $volopt "$vollabel" -o \"$iso\" \"$tree\"" > "$viewpipe"
        $mkisofs_base $volopt "$vollabel" -o "$iso" "$tree" 2> "$viewpipe" > "$viewpipe"
    else
        $mkisofs_base $volopt "$vollabel" -o "$iso" "$tree" # send output to task dlg
    fi
    if [ $? -eq 0 ]; then
        reply="isook"
    else
        reply="isofail"
    fi
    if [ -p "$respipe" ]; then
        echo "$reply" > "$respipe"
    fi
    exit
elif [ "$1" = "--copyiso" ]; then
    # copy an iso file from drive
    drive="$2"
    iso="$3"
    type="$4"
    vollabel="$5"  # ignored
    echo "--- Copying image from $drive..." > "$viewpipe"
    if (( verbose )); then
        echo "    as $iso" > "$viewpipe"
    fi
    if ! checkprog; then
        echo "isofail" > "$respipe"
        exit 1
    fi
    #rm -f "$iso"
    
    if (( verbose )); then
        echo ">>> dd if=$drive of=\"$iso\"" > "$viewpipe"
    	dd if=$drive of="$iso" 2> "$viewpipe" > "$viewpipe"
    else
    	dd if=$drive of="$iso" 2> "$viewpipe" >/dev/null
    fi
    if [ $? -eq 0 ]; then
        reply="isook"
    else
        reply="isofail"
    fi
    if [ -p "$respipe" ]; then
        echo "$reply" > "$respipe"
    fi
    exit
elif [ "$1" = "--burniso" ]; then
    # burn an iso file
    # type is currently ignored, but you can use it to modify the burn
    # command based on media type or a custom selected type.
    burner="$2"
    iso="$3"
    type="$4"
    if [ "$5" = "" ]; then
        speed=""
    else
        speed="speed=$5"
    fi
    if [ "$6" = "1" ]; then
        blank="blank=fast"
    else
        blank=""
    fi
    echo "--- Burning..." > "$viewpipe"
    if (( verbose )); then
        echo "    from image $iso" > "$viewpipe"
    fi
    if ! checkprog; then
        echo "burnfail" > "$respipe"
        exit 1
    fi

    if (( verbose )); then
        echo ">>> $cdrecord -v $speed $blank -fs=8m -dev=$burner -data -dao \"$iso\"" \
                                                                    > "$viewpipe"
        grace=""
    else
        grace="gracetime=0"
    fi
    
    # cannot use a named pipe here because read opens/closes the pipe repeatedly
    # causing a SIGPIPE signal which terminates cdrecord and cdrskin with exit
    # status 141
    IFS_OLD="$IFS"
    IFS=$'\n'
    ( $cdrecord -v $grace $speed $blank -fs=8m -dev=$burner -data -dao "$iso" \
                                    2>&1 \
                                    && echo "burnok" > "$respipe" \
                                    || echo "burnfail" > "$respipe" ) | setstatus
    IFS="$IFS_OLD"
    exit
fi

