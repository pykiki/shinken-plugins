#!/bin/bash

LOGFILE=$1

SLOW_WARNING=1
SLOW_CRITICAL=5

MINUTES=5

# Try pgbadger
pgbadger=$(pgbadger -x text -o - -v $LOGFILE -f stderr --begin "$(date --date="$MINUTES minutes ago" '+%Y-%m-%d %H:%M:%S')" 2>/dev/null)

ret=$?

if [ $ret -gt 1 ]; then
    if [ $ret -eq 2 ]; then
        echo "UNKNOWN: $LOGFILE doesn't exist"
        exit 3
    elif [ $ret -eq 13 ]; then
        echo "UNKNOWN: Can't open file $LOGFILE, permission denied"
        exit 3
    elif [ $ret -eq 127 ]; then
        echo "UNKNOWN: pgbadger command not found"
        exit 3
    elif [ $ret -eq 255 ]; then
        echo "UNKNOWN: Unknown log format in $LOGFILE"
        exit 3
    else
        echo "UNKNOWN: pgbadger returned $ret"
        exit 3
    fi
fi

# Get counters
total=$(echo "$pgbadger" | grep '^Number of queries:' | cut -d ' ' -f 4 | sed 's/,//')
[ -z "$total" ] && total=0

nb_select=$(echo "$pgbadger" | grep '^SELECT:'| cut -d ' ' -f 2 | sed 's/,//')
nb_insert=$(echo "$pgbadger" | grep '^INSERT:'| cut -d ' ' -f 2 | sed 's/,//')
nb_update=$(echo "$pgbadger" | grep '^UPDATE:'| cut -d ' ' -f 2 | sed 's/,//')
nb_delete=$(echo "$pgbadger" | grep '^DELETE:'| cut -d ' ' -f 2 | sed 's/,//')
nb_others=$(echo "$pgbadger" | grep '^OTHERS:'| cut -d ' ' -f 2 | sed 's/,//')

[ -z "$nb_select" ] && nb_select=0
[ -z "$nb_insert" ] && nb_insert=0
[ -z "$nb_update" ] && nb_update=0
[ -z "$nb_delete" ] && nb_delete=0
[ -z "$nb_others" ] && nb_others=0

# Convert to frequency per minute
select_per_m=$(echo "scale=2;$nb_select/5" | bc)
insert_per_m=$(echo "scale=2;$nb_insert/5" | bc)
update_per_m=$(echo "scale=2;$nb_update/5" | bc)
delete_per_m=$(echo "scale=2;$nb_delete/5" | bc)
others_per_m=$(echo "scale=2;$nb_others/5" | bc)

peak=$(echo "$pgbadger" | grep '^Query peak:' | cut -d ' ' -f 3 | sed 's/,//')
[ -z "$peak" ] && peak=0

# Count slow queries (more than 1000ms)
nb_slow=$(dategrep $LOGFILE --last-minutes $MINUTES --format '%Y-%m-%d %H:%M:%S' 2>/dev/null | egrep 'duration: [0-9]{4,}\.' -o | wc -l)
slow_per_s=$(echo "scale=3;$nb_slow/5/60" | bc)


msg="$total queries logged on last $MINUTES minutes | select=${select_per_m}rpm;;;;; insert=${insert_per_m}rpm;;;;; update=${update_per_m}rpm;;;;; delete=${delete_per_m}rpm;;;;; others=${others_per_m}rpm;;;;; peak=${peak}rps;;;;; slow=${slow_per_s}rps;$SLOW_WARNING;$SLOW_CRITICAL;;;"


if [ "$slow_per_s" -gt "$SLOW_CRITICAL" ]; then
    echo "CRITICAL - $slow_per_s slow queries over $msg"
    exit 2
elif [ "$slow_per_s" -gt "$SLOW_WARNING" ]; then
    echo "WARNING - $slow_per_s slow queries over $msg"
    exit 1
else
    echo "OK - $msg"
    exit 0
fi
