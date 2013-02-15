#!/bin/bash
$fm_import

# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# config.sh:  This script sets up the initial configuration and is sourced by
#             several scripts.  Set preferred burning programs here.


# cdrecord, cdrskin or wodim may be specified for default_cdrecord.  mkisofs
# or xorrisofs for default_mkisofs
default_cdrecord=cdrecord
default_mkisofs=mkisofs
default_isoinfo=isoinfo

version=0.5.1

# initial defaults
default_burner=/dev/sr0
default_types="unknown\nCD-R\nCD+R\nCD-RW\nCD+RW\nDVD-R\nDVD+R\nDVD-RW\nDVD+RW\nDVD-R/DL\nDVD+R/DL\nBD-R\nBD-RE\nBD-R/DL\nBD-RE/DL"
default_speeds="Max\n1x\n2x\n3x\n4x\n6x\n8x\n12x\n16x\n24x\n32x\n48x"
# small temp dir
default_tmpdir="$fm_tmp_dir"
default_blocksize=2048

# Maximum disc capacities in 2048 byte blocks
     cdlimit=359844
   dvdlimit=2295104
  duallimit=4173824
  bdrlimit=12219392
bdrdllimit=24438784

# establish and read config files
mkdir -p "$fm_cmd_data/config"

if [ -d "$default_tmpdir" ]; then
    tmpdir="$default_tmpdir"
else
    tmpdir="/tmp"
fi
largetmpdirfile="$fm_cmd_data/config/largetmpdir"

alarmcmdfile="$fm_cmd_data/config/alarmcmd"
verbosefile="$fm_cmd_data/config/verbose"

typelist="$fm_cmd_data/config/typelist"
if [ ! -e "$typelist" ]; then
    echo -e "$default_types" > "$typelist"
fi
speedlist="$fm_cmd_data/config/speedlist"
if [ ! -s "$speedlist" ]; then
    echo -e "$default_speeds" > "$speedlist"
fi

burnerfile="$fm_cmd_data/config/burner"
burner="`head -n 1 "$burnerfile" 2>/dev/null`"
if [ "$burner" = "" ]; then
    burner="$default_burner"
    echo "$burner" > "$burnerfile"
fi

choosersizefile="$fm_cmd_data/config/choosersize"
if [ ! -e "$choosersizefile" ]; then
    echo "800x600" > "$choosersizefile"
fi
export choosersizefile

blocksize=$default_blocksize
if (( blocksize == 0 )); then
    blocksize=2048
fi

