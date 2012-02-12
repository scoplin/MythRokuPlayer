#!/bin/bash

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
$(basename $0) [ -n | --dry-run ] <mythdir> <mpg file>

$(basename $0) will attempt to encode an mpeg file to mp4
using the handbrake CLI.  It will also optionally update
the database and remove the original file, but those
options must be explicitly enabled.
EOL
    exit $rc
}

if [[ "-h" = "$1" || "--help" = "$1" ]]; then
    usage
fi

[[ $# -eq 2 ]] || usage "Incorrect number of arguments"

# convert mpeg file to mp4 using handbrakecli
MYTHDIR=$1
MPGFILE=$2

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

UPDATE_DATABASE=${UPDATE_DATABASE:-true}
HANDBRAKE_ARGS=${HANDBRAKE_ARGS:-"--preset='iPhone & iPod Touch'"}
LOGFILE=${LOGFILE:-"/var/log/mythtv/rokuencode.%s.log"}
GENERATE_PREVIEWS=${LOGFILE:-"/var/log/mythtv/rokuencode.%s.log"}

# Calculate the new base name
newbname=$(echo $MPGFILE | sed 's/\(.*\)\..*/\1_roku/')
log=$(printf "$LOGFILE" $newbname)

# Execute everything else in a subshell directed to the log
(

if [[ -n "$DRY_RUN" ]]; then
    echo "Dry run only.  No actions will be performed.  Configuration is:"
    echo "    UPDATE_DATABASE=${UPDATE_DATABASE}"
    echo "    HANDBRAKE_ARGS=${HANDBRAKE_ARGS}"
    echo "    LOGFILE=${LOGFILE}"
    echo "    GENERATE_PREVIEWS=${GENERATE_PREVIEWS}"
    exit 0;
fi

newname="$MYTHDIR/${newbname}.mp4"
echo "Roku Encode $MPGFILE to $newname"
/usr/bin/HandBrakeCLI $HANDBRAKE_ARGS -i $MYTHDIR/$MPGFILE -o $newname

echo "Generate Previews"
#Mythtv seems to have problems with keyframes in mp4s, so make previews with ffmpeg
#   ffmpeg -loglevel quiet -ss 34 -vframes 1 -i $newname -y -f image2  $MYTHDIR/$newname.png
#   ffmpeg -loglevel quiet -ss 34 -vframes 1 -i $newname -y -f image2 -s 100x75 $MYTHDIR/$newname.64.100x75.png
#   ffmpeg -loglevel quiet -ss 34 -vframes 1 -i $newname -y -f image2 -s 320x240 $MYTHDIR/$newname.64.320x240.png


if [[ "$UPDATE_DATABASE" = "true" ]]; then
echo "Database/remove"
# remove the orignal mpg and update the db to point to the mp4
NEWFILESIZE=$(du -b "$newname" | cut -f1)
mysql --user=$DBUserName --password=$DBPassword --host=$DBHostName $DBName <<EOL
UPDATE recorded SET basename='$newbname.mp4',filesize='$NEWFILESIZE',transcoded='1' WHERE basename='$MPGFILE';
EOL
#rm $MYTHDIR/$MPGFILE
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
) 2>&1 | \
while read line; do
    echo "$(date --rfc-3339=seconds): $line"
done > $log

