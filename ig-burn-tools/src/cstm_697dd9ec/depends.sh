#!/bin/bash

# Burn Tools ( a SpaceFM Plugin ) by IgnorantGuru
# License: GPL2+  ( See README )
#
# depends.sh:  This source script tests dependencies and exits with status 1
#              if unsatisfied.  It also discovers what burn and other
#              programs are available for use.


# TIP: Set your preferred program defaults in config.sh, not here

if [ "$default_cdrecord" = "" ]; then
    default_cdrecord=cdrecord
fi
if [ "$default_mkisofs" = "" ]; then
    default_mkisofs=mkisofs
fi
if [ "$default_isoinfo" = "" ]; then
    default_isoinfo=isoinfo
fi
cdrecord=`which $default_cdrecord 2>/dev/null`
mkisofs=`which $default_mkisofs 2>/dev/null`
isoinfo=`which $default_isoinfo 2>/dev/null`
# if cdrecord not in PATH look in /opt/schily/bin
if [ "$cdrecord" = "" ] && [ "$default_cdrecord" = "cdrecord" ] && \
                                        [ -x /opt/schily/bin/cdrecord ]; then
    cdrecord=/opt/schily/bin/cdrecord
    mkisofs=/opt/schily/bin/mkisofs
fi                                            
if [ -h "$cdrecord" ]; then
    realcdrecord=`readlink "$cdrecord"`
else
    realcdrecord="$cdrecord"
fi
if [ -h "$cdrecord" ] && [ "$realcdrecord" != "${realcdrecord%wodim}" ] && \
                               [ -x /opt/schily/bin/cdrecord ]; then
    # avoid link cdrecord -> wodim if /opt/schily version present
    cdrecord=/opt/schily/bin/cdrecord
    mkisofs=/opt/schily/bin/mkisofs
else
    if [ "$cdrecord" = "" ]; then
        cdrecord=`which cdrskin 2>/dev/null`
    fi
    if [ "$cdrecord" = "" ]; then
        cdrecord=`which wodim 2>/dev/null`
    fi
fi
if [ "$mkisofs" = "" ]; then
    mkisofs=`which xorrisofs 2>/dev/null`
fi
if [ "$mkisofs" = "" ]; then
    mkisofs=`which genisoimage 2>/dev/null`
fi
udevil=`which udevil 2>/dev/null`
eject=`which eject 2>/dev/null`
unset msg
if [ "$cdrecord" = "" ]; then
    msg="    cdrecord (cdrtools)  OR  cdrskin  OR  wodim (cdrkit)"$'\n'
fi
if [ "$mkisofs" = "" ]; then
    msg="$msg    mkisofs (cdrtools)   OR  xorrisofs (xorriso)  OR  genisoimage (cdrkit)"$'\n'
fi
if [ "$udevil" = "" ]; then
    msg="$msg    udevil"$'\n'
fi
if [ "$eject" = "" ]; then
    msg="$msg    eject"$'\n'
fi
if ! spacefm --version 1>/dev/null 2>/dev/null; then
    msg="$msg    spacefm >= 0.8.3"$'\n'
fi
if [ "$msg" != "" ]; then
    echo "This plugin requires the following missing dependencies:"
    echo "$msg"
    exit 1
fi

export mkisofs
export cdrecord

