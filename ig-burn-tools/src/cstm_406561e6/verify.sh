#!/bin/bash
$fm_import

# IG Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# verify.sh:  This script verifies disc contents by one of three methods.  A
#             copy of this script is also used by the Verify Disc command.


if [ "$1" = "--verbose" ]; then
    verbose=1
    shift
else
    verbose=0
fi

burn_verify="$1"
burner="$2"
tree="$3"
iso="$4"
point="$5"
if [ "$tree" != "/" ]; then
    # strip trailing slash
    tree="${tree%/}"
fi

if [ ! -p "$respipe" ]; then
    respipe=/dev/null
fi
if [ ! -p "$cmdpipe" ]; then
    cmdpipe=/dev/null
fi
if [ ! -p "$viewpipe" ]; then
    viewpipe=/dev/stdout
fi

setprogress()
{
    (( percent = completed * 100 / deepsize ))
    (( completedm = completed / 1024 / 1024 ))
    spacefm -s set-task --window $fm_my_window $fm_my_task progress $percent 2>/dev/null &
    echo "set progress1 $percent %   ( $completedm M / $deepsizem M )" > "$cmdpipe" &
}

if [ "$burn_verify" = "Verify Checksums" ]; then
    cd "$point"
    if [ -e "$point/.checksum.md5" ]; then
        if (( verbose )); then
            echo ">>> md5sum -c --warn \"$point/.checksum.md5\"" > "$viewpipe"
            md5sum -c --warn "$point/.checksum.md5" 2> "$viewpipe" > "$viewpipe"
        else
            md5sum -c --warn "$point/.checksum.md5" 2> "$viewpipe" # output to task dialog
        fi
    elif [ -e "$point/.checksum.md5.gz" ]; then
        if (( verbose )); then
            echo ">>> cat \"$point/.checksum.md5.gz\" | gzip -d | md5sum -c --warn" > "$viewpipe"
            cat "$point/.checksum.md5.gz" | gzip -d | md5sum -c --warn 2> "$viewpipe" > "$viewpipe"
        else
            cat "$point/.checksum.md5.gz" | gzip -d | md5sum -c --warn 2> "$viewpipe" # output to task dialog
        fi
    else
        echo "*** Missing $point/.checksum.md5[.gz] - cannot verify checksums" > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
    fi
    if [ $? -eq 0 ]; then
        echo "verifyok" > "$respipe"
        exit 0
    else
        echo "verifyfail" > "$respipe"
        exit 1
    fi
elif [ "$burn_verify" = "Compare To Dir" ]; then
	# Compare all files in burn dir (and subfolders) to moint point
	# Symlinks are followed
    if [ ! -d "$tree" ]; then
        echo "*** Missing Burn Dir $tree" > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
    fi

    # get deep size
    deepsize="$(du -csL "$tree" 2>"$viewpipe")"
    if [ $? -ne 0 ]; then
        echo "errors reading $tree" > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
    fi
    deepsize="$(echo "$deepsize" | tail -n 1)"
    deepsize="${deepsize%%[[:blank:]]*}"
    (( deepsize = deepsize * 1024 ))
    (( deepsizem = deepsize / 1024 ))
    completed=0
    setprogress

    IFS_OLD="$IFS"
    IFS=$'\n'
 	diffcount=0
	filecount=0
    prosize=0
    treelen=${#tree}
	for f1 in `find -L "$tree" -type f`;
	do
        f2="${f1:$treelen}"
        f2="${f2#/}"
        f2="$point/$f2"
		(( filecount +=1 ))
		if [ -e "$f2" ]; then
            if (( verbose )); then
                echo ">>> cmp -s \"$f1\" \"$f2\"" > "$viewpipe"
            fi
            cmp -s "$f1" "$f2"
			if [ $? -ne 0 ]; then
				echo "DIFFERS: $f2" > "$viewpipe"
				(( diffcount +=1 ))
			fi
		else
			echo "MISSING: $f2" > "$viewpipe"
			(( diffcount +=1 ))
		fi
        fsize=`stat -Lc %s "$f1"`
        (( completed += fsize ))
        # don't setprogress too rapidly on small files
        (( prosize += fsize ))
        if (( prosize > 26214400 )); then
            prosize=0
            setprogress
        fi
	done
    IFS="$IFS_OLD"

    completed=$deepsize
    setprogress
    if (( filecount == 0 )); then
		echo 'ERROR: No files found.' > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
	elif (( diffcount == 0 )); then
		echo "All $filecount files are equal." > "$viewpipe"
        echo "verifyok" > "$respipe"
        exit 0
	else
		echo "WARNING: $diffcount of $filecount files differ." > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
	fi
elif [ "$burn_verify" = "Compare To Image" ]; then
    # Method by OmegaPhil
    if [ ! -f "$iso" ]; then
        echo "*** Missing Image $iso" > "$viewpipe"
        echo "verifyfail" > "$respipe"
        exit 1
    fi
    isosize=`stat -Lc %s "$iso"`
    info="`udevil info "$burner" 2> "$viewpipe"`"
    blocksize="`echo "$info" | grep -m 1 "^  block size:" | sed 's/.*: *\(.*\)/\1/'`"
    if (( blocksize == 0 )); then
        blocksize=2048
    fi
    # Calculating number of blocks from the device to return
    (( blocks = isosize / blocksize ))
    if (( verbose )); then
        vrb="--verbose"
        echo ">>> dd if=\"$burner\" count=$blocks bs=$blocksize | cmp $vrb - \"$iso\"" > "$viewpipe"
    else
        vrb=
    fi
    dd if="$burner" count=$blocks bs=$blocksize | cmp $vrb - "$iso" 2> "$viewpipe" > "$viewpipe"
    if [ $? -eq 0 ]; then
        echo "verifyok" > "$respipe"
        exit 0
    else
        echo "verifyfail" > "$respipe"
        exit 1
    fi
fi

