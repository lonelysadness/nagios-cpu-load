#!/bin/bash

# Location of the data file
DATA_FILE="XXXX"
MAX_LINES=1440 # To store up to 24 hours of data

# Check if iostat is accessible
if ! command -v /usr/bin/iostat &> /dev/null
then
    echo "UNKNOWN: iostat not found"
    exit 3
fi

# Check if the data file is writable
if ! touch "$DATA_FILE" &> /dev/null
then
    echo "UNKNOWN: Unable to write to $DATA_FILE"
    exit 3
fi

# Default threshold values
WARN_1_MIN=70
CRIT_1_MIN=90
WARN_5_MIN=60
CRIT_5_MIN=80
WARN_15_MIN=50
CRIT_15_MIN=70

# Nagios exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Collects and stores CPU load
collect_cpu_load() {
    local cpu_load=$(/usr/bin/iostat -c 1 2 | awk '/^avg-cpu:/{i++}i==2{getline; print $1; exit}')
    echo "$(date +%s) $cpu_load" >> "$DATA_FILE"
    tail -n $MAX_LINES "$DATA_FILE" > "${DATA_FILE}.tmp"
    mv "${DATA_FILE}.tmp" "$DATA_FILE"
}

# Calculates the average CPU load
calculate_average() {
    local time_period=$1
    local end_time=$(date +%s)
    local start_time=$((end_time - time_period * 60))
    awk -v start=$start_time -v end=$end_time '$1 >= start && $1 <= end { total += $2; count++ } END { if (count > 0) print total/count; else print 0; }' "$DATA_FILE"
}

# Checks thresholds
check_thresholds() {
    local avg_load=$1
    local warn_threshold=$2
    local crit_threshold=$3
    local period=$4

    if (( $(echo "$avg_load >= $crit_threshold" | /usr/bin/bc -l) )); then
        echo "CRITICAL: Average CPU load over $period minute(s) is $avg_load%, CRITICAL Threshold: $crit_threshold%"
        return $CRITICAL
    elif (( $(echo "$avg_load >= $warn_threshold" | /usr/bin/bc -l) )); then
        echo "WARNING: Average CPU load over $period minute(s) is $avg_load%, WARNING Threshold: $warn_threshold%"
        return $WARNING
    else
        echo "OK: Average CPU load over $period minute(s) is $avg_load%, All is normal"
        return $OK
    fi
}

# Collects CPU load
collect_cpu_load

# Periods to check
periods=("1" "5" "15")
warn_thresholds=($WARN_1_MIN $WARN_5_MIN $WARN_15_MIN)
crit_thresholds=($CRIT_1_MIN $CRIT_5_MIN $CRIT_15_MIN)

highest_status=$OK

for i in "${!periods[@]}"; do
    avg_load=$(calculate_average ${periods[$i]})
    check_thresholds $avg_load ${warn_thresholds[$i]} ${crit_thresholds[$i]} ${periods[$i]}
    status=$?
    if [ $status -gt $highest_status ]; then
        highest_status=$status
    fi
done

exit $highest_status
