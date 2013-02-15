#!/bin/bash
$fm_import

# IG Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# checksums.sh:  This script creates checksums for files on a disc.


setprogress()
{
    (( percent = completed * 100 / deepsize ))
    (( completedm = completed / 1024 / 1024 ))
    spacefm -s set-task --window $fm_my_window $fm_my_task progress $percent 2>/dev/null &
    echo "set progress1 $percent %   ( $completedm M / $deepsizem M )" > "$cmdpipe" &
}

if [ "$1" = "--verbose" ]; then
    verbose=1
    shift
else
    verbose=0
fi
tree="$1"
if [ ! -d "$tree" ]; then
    echo "checksums: invalid Burn Dir $tree" > "$viewpipe"
    echo "checksumsfail" > "$respipe"
    exit 1
fi

# get deep size
deepsize="$(du -csL "$tree" 2>"$viewpipe")"
if [ $? -ne 0 ]; then
    echo -e "\nchecksums: errors reading $tree" > "$viewpipe"
    echo "checksumsfail" > "$respipe"
    exit 1
fi
deepsize="$(echo "$deepsize" | tail -n 1)"
deepsize="${deepsize%%[[:blank:]]*}"
(( deepsize = deepsize * 1024 ))
(( deepsizem = deepsize / 1024 / 1024 ))
completed=0
setprogress

# read old sums
if [ -e "$tree/.checksum.md5.gz" ]; then
    cat "$tree/.checksum.md5.gz" | gzip -d > "$tree/.checksum.md5-old.tmp"
else
    rm -f "$tree/.checksum.md5-old.tmp"
fi
oldx=0
unset md5_old md5_old_sum
declare -a md5_old
declare -a md5_old_sum
IFS_OLD="$IFS"
IFS=$'\n'
for f in "$tree/.checksum.md5-old.tmp" "$tree/.checksum.md5.tmp"; do
    if [ -s "$f" ]; then
        for l in `cat "$f"`; do
            lsum="${l%% *}"
            lname="${l#* }"
            lname="${lname:1}"
            if [ "${#lsum}" -eq 32 ] && [ "$lname" != "" ]; then
                md5_old[$oldx]="$lname"
                md5_old_sum[$oldx]="$lsum"
                (( oldx++ ))
            fi
        done
    fi
done
rm -f "$tree/.checksum.md5.tmp"
rm -f "$tree/.checksum.md5-old.tmp"

# get and parse file list
cd "$tree"
denied=0
prosize=0
flist=`find -L -type f`
if [ "$flist" != "" ]; then
    x=0
    for f in $flist; do
        f="${f#./}"
        fsize=`stat -Lc %s "$f"`
        if [ ! -r "$f" ]; then
            echo "checksums: Permission denied: $tree/$f"
            denied=1
            break
        fi
        if [ "$f" != ".checksum.md5.gz" ]; then
            # have old md5?
            have_it=0
            while [ "${md5_old[$x]}" != "" ]; do
                if [ "${md5_old[$x]}" = "$f" ]; then
                    # reuse old md5
                    if (( verbose )); then
                        echo "reusing md5sum for $f" > "$viewpipe"
                    fi
                    echo "${md5_old_sum[$x]} *$f" >> "$tree/.checksum.md5.tmp"
                    have_it=1
                    break
                fi
                (( x++ ))
            done
            if (( have_it == 0 )); then
                # new md5
                if (( verbose )); then
                    echo ">>> md5sum -b \"$f\"" > "$viewpipe"
                fi
                md5sum -b "$f" 2> "$viewpipe" >> "$tree/.checksum.md5.tmp"
                if [ $? -ne 0 ]; then
                    echo "checksums: md5sum error" > "$viewpipe"
                    echo "checksumsfail" > "$respipe"
                    exit 1
                fi
            fi
        fi
        (( completed += fsize ))
        # don't setprogress too rapidly on small files
        (( prosize += fsize ))
        if (( prosize > 52428800 )); then
            prosize=0
            setprogress
        fi
    done
fi
IFS="$IFS_OLD"
unset md5_old md5_old_sum
unset flist
rm -f "$tree/.checksum.md5.gz"
if [ -e "$tree/.checksum.md5.tmp" ]; then
    cat "$tree/.checksum.md5.tmp" | gzip > "$tree/.checksum.md5.gz"
fi
rm -f "$tree/.checksum.md5.tmp"

if (( denied == 1 )); then
    echo -e "\nchecksums: errors reading $tree" > "$viewpipe"
    echo "checksumsfail" > "$respipe"
    exit 1
fi

completed=$deepsize
setprogress
echo "checksumsok" > "$respipe"

