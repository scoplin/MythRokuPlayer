#!/bin/bash

# Don't tolerate errors
set -o pipefail
set -e

DRY_RUN=
if [[ "-n" = "$1" || "--dry-run" = "$1" ]]; then
    # It's a dry run
    DRY_RUN=true
    shift
fi

function usage {
    if [[ $# -eq 0 ]]; then
        rc=0
    else
        rc=1
        echo $* >&2
        echo
    fi
    cat >&2 <<EOL
$(basename $0) [ -n | --dry-run ] <mythdir> <mpg file> <command> [ <jobid> ]

$(basename $0) will attempt to encode an mpeg file to mp4
using the handbrake CLI.  It will also optionally update
the database and remove the original file, but those
options must be explicitly enabled.

If the jobid is provided, this will update the jobqueue
table with status information from HandBrakeCLI.

Command can be one of the following
    encode - Encodes an mpg file to an mp4
    reset  - Resets the database back to the original recording
EOL
    exit $rc
}

if [[ "-h" = "$1" || "--help" = "$1" ]]; then
    usage
fi

[[ $# -eq 3 ]] || [[ $# -eq 4 ]] || usage "Incorrect number of arguments"

MYTHDIR=$1
MPGFILE=$2
COMMAND=$3
JOBID=$4

# Function to find a readable file in list of possible locations
function findFile {
    for file in $*; do
        test -r "$file" && echo "$file" && break
    done
}

# Load conversion configuration
ROKU_ENCODE_CONFIG_FILES="/usr/local/share/mythtv/rokuencode.txt \
    /usr/share/mythtv/rokuencode.txt \
    /usr/local/etc/mythtv/rokuencode.txt \
    /etc/mythtv/rokuencode.txt \
    ~/.mythtv/rokuencode.txt \
    rokuencode.txt"
ROKU_ENCODE_CONFIG_FILE=$(findFile $ROKU_ENCODE_CONFIG_FILES)

# Standard locations from which to load configuration
# This code is roughly translated from the php in MythTV.php
MYSQL_CONFIG_FILES="/usr/local/share/mythtv/mysql.txt \
    /usr/share/mythtv/mysql.txt \
    /usr/local/etc/mythtv/mysql.txt \
    /etc/mythtv/mysql.txt \
    ~/.mythtv/mysql.txt \
    mysql.txt"
MYSQL_CONFIG_FILE=$(findFile $MYSQL_CONFIG_FILES)

if [ -z "$MYSQL_CONFIG_FILE" ]; then
    echo "Failed to load MySQL configuration." >&2
    exit 1
fi

. $MYSQL_CONFIG_FILE

if [ -z "$ROKU_ENCODE_CONFIG_FILE" ]; then
    echo "Failed to load Roku encoder configuration.  Assuming defaults." >&2
else
    . $ROKU_ENCODE_CONFIG_FILE
fi

# Validate/normalize jobid
JOBID=$(
mysql -N --user=$DBUserName --password=$DBPassword --host=$DBHostName $DBName <<EOL
SELECT id
FROM jobqueue
WHERE id='$JOBID'
EOL
)

UPDATE_DATABASE=${UPDATE_DATABASE:-true}
REMOVE_ORIGINAL=${REMOVE_ORIGINAL:-false}
HANDBRAKE_ARGS=${HANDBRAKE_ARGS:-"--preset='iPhone & iPod Touch'"}
LOGFILE=${LOGFILE:-"/var/log/mythtv/rokuencode.%s.log"}
GENERATE_PREVIEWS=${GENERATE_PREVIEWS:-true}

# Calculate the base name for the file
basename=$(echo $MPGFILE | sed 's/\(.*\)\..*/\1/')

function process_command {
    echo "Configuration is:"
    echo "    COMMAND=${COMMAND}"
    echo "    UPDATE_DATABASE=${UPDATE_DATABASE}"
    echo "    REMOVE_ORIGINAL=${REMOVE_ORIGINAL}"
    echo "    HANDBRAKE_ARGS=${HANDBRAKE_ARGS}"
    echo "    LOGFILE=${LOGFILE}"
    echo "    GENERATE_PREVIEWS=${GENERATE_PREVIEWS}"

    if [[ -n "$DRY_RUN" ]]; then
        echo "Dry run only.  No actions will be performed."
        exit 0;
    fi

    case $COMMAND in
        encode)
          doencode || exit $?
          ;;
        reset)
          doreset || exit $?
          ;;
    esac
}

# A function that reads its stdin for HandBrakeCLI status output and sends through
# updates with each whole increase in % complete.  It will also send those updates
# to the jobqueue table
function handbrake_progress {
    oldpercent=0
    while read status; do
        percent=$(echo "$status" | sed -e 's/.* \([0-9]*\)\.[0-9][0-9] %.*/\1/')
        if [[ "$oldpercent" != "$percent" ]]; then
            if [[ -n "$JOBID" ]]; then
                mysql --user=$DBUserName --password=$DBPassword --host=$DBHostName $DBName <<EOL
UPDATE jobqueue
SET comment='$status'
WHERE id=$JOBID
EOL
            fi
            echo "$status"
            oldpercent=$percent
        fi
    done
}

function doencode {
    newname="$MYTHDIR/${basename}.mp4"
    echo "Roku Encode $MPGFILE to $newname"
    # Translate carriage returns to newlines for the log, and report progress sanely
    set -o pipefail
    /usr/bin/HandBrakeCLI $HANDBRAKE_ARGS -i $MYTHDIR/$MPGFILE -o $newname | tr '\015' '\n' | handbrake_progress
    [[ $? -eq 0 ]] || exit $?

    if [[ "$GENERATE_PREVIEWS" = "true" ]]; then
        echo "Generate Previews"
        # Mythtv seems to have problems with keyframes in mp4s, so make previews with ffmpeg
        ffmpeg -loglevel quiet -ss 64 -vframes 1 -i $newname -y -f image2  $MYTHDIR/$newname.png
        ffmpeg -loglevel quiet -ss 64 -vframes 1 -i $newname -y -f image2 -s 100x75 $MYTHDIR/$newname.-1.100x75.png
        ffmpeg -loglevel quiet -ss 64 -vframes 1 -i $newname -y -f image2 -s 100x56 $MYTHDIR/$newname.-1.100x56.png
        ffmpeg -loglevel quiet -ss 64 -vframes 1 -i $newname -y -f image2 -s 320x240 $MYTHDIR/$newname.-1.320x240.png
    fi


    if [[ "$UPDATE_DATABASE" = "true" ]]; then
        echo "Database/remove"
        # update the db to point to the mp4
        NEWFILESIZE=$(du -b "$newname" | cut -f1)
        mysql --user=$DBUserName --password=$DBPassword --host=$DBHostName $DBName <<EOL
UPDATE recorded
SET basename='$basename.mp4',filesize='$NEWFILESIZE',transcoded='1'
WHERE basename='$MPGFILE';
EOL
        if [[ "$REMOVE_ORIGINAL" = "true" ]]; then
            rm -f $MYTHDIR/$MPGFILE
            rm -f $MYTHDIR/$MPGFILE*.png
        else
            mv $MYTHDIR/$MPGFILE $MYTHDIR/$MPGFILE.old
        fi
    fi
    
    # Make the bif files for trick play
    #   cd $MYTHDIR
    # If it's HD we assume it's 16:9
    #   echo "makebif HD"
    #   /usr/local/bin/makebif.py -m 3 $newname
    # If it's SD we assume it's 4:3
    #   echo "$makebif SD"
    #   /usr/local/bin/makebif.py -m 0 $newname

    echo "Complete"
}

# Function to restore the original recording in the database
function doreset {
    # update the db to point to the mpg
    newname="$MYTHDIR/${basename}.mpg"
    if [[ "$UPDATE_DATABASE" = "true" && -r "$newname.old" ]]; then
    mv $newname.old $newname
    NEWFILESIZE=$(du -b "$newname" | cut -f1)
    mysql --user=$DBUserName --password=$DBPassword --host=$DBHostName $DBName <<EOL
UPDATE recorded
SET basename='$basename.mpg',filesize='$NEWFILESIZE',transcoded='0'
WHERE basename='$MPGFILE';
EOL
    rm -f $MYTHDIR/$MPGFILE
    rm -f $MYTHDIR/$MPGFILE*.png
fi
}

# Set up logging and execute
if [[ -n "LOGFILE" ]]; then
    log=$(printf "$LOGFILE" $basename)
    echo "Roku $COMMAND $MPGFILE.  Logging to $log"
    set -o pipefail
    process_command 2>&1 | \
        while read line; do
            echo "$(date --rfc-3339=seconds): $line"
        done >> $log
else
    echo "Roku $COMMAND $MPGFILE.  Logging to console"
    process_command || exit $?
fi
