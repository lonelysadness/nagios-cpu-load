#!/bin/bash

# Default settings
DATA_FILE="/var/tmp/cpu_load_data"
MAX_LINES=1440 # To store up to 24 hours of data

# Nagios exit codes
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# Display help
display_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -f, --data-file      Specify the data file path (default: $DATA_FILE)"
    echo "  -t, --thresholds     Set thresholds in format '1:warn,crit-5:warn,crit-15:warn,crit'"
    echo "                       Example: -t 1:70,90-5:60,80-15:50,70"
}

# Parse thresholds
parse_thresholds() {
    IFS='-' read -ra ADDR <<< "$1"
    for i in "${ADDR[@]}"; do
        IFS=':' read time values <<< "$i"
        IFS=',' read warn crit <<< "$values"
        case $time in
            1) WARN_1_MIN=$warn; CRIT_1_MIN=$crit ;;
            5) WARN_5_MIN=$warn; CRIT_5_MIN=$crit ;;
            15) WARN_15_MIN=$warn; CRIT_15_MIN=$crit ;;
        esac
    done
}

# Parse arguments
parse_arguments() {
    DATA_FILE=$DATA_FILE
    WARN_1_MIN=70; CRIT_1_MIN=90
    WARN_5_MIN=60; CRIT_5_MIN=80
    WARN_15_MIN=50; CRIT_15_MIN=70

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                display_help
                exit 0
                ;;
            -f|--data-file)
                DATA_FILE=$2
                shift 2
                ;;
            -t|--thresholds)
                parse_thresholds $2
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                display_help
                exit $UNKNOWN
                ;;
        esac
    done
}

# Check if iostat is accessible
if ! command -v iostat &> /dev/null; then
    echo "UNKNOWN: iostat not found"
    exit $UNKNOWN
fi

# Check and prepare the data file
if [[ ! -f "$DATA_FILE" ]]; then
    if ! touch "$DATA_FILE" &> /dev/null; then
        echo "UNKNOWN: Unable to create $DATA_FILE"
        exit $UNKNOWN
    fi
    chmod 600 "$DATA_FILE" &> /dev/null
fi

if ! [ -w "$DATA_FILE" ]; then
    echo "UNKNOWN: Unable to write to $DATA_FILE"
    exit $UNKNOWN
fi

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

# Checks thresholds and returns message with status
check_thresholds() {
    local avg_load=$1
    local warn_threshold=$2
    local crit_threshold=$3
    local period=$4

    if (( $(echo "$avg_load >= $crit_threshold" | /usr/bin/bc -l) )); then
        echo "$CRITICAL:CRITICAL: Average CPU load over $period minute(s) is $avg_load%, CRITICAL Threshold: $crit_threshold%"
    elif (( $(echo "$avg_load >= $warn_threshold" | /usr/bin/bc -l) )); then
        echo "$WARNING:WARNING: Average CPU load over $period minute(s) is $avg_load%, WARNING Threshold: $warn_threshold%"
    else
        echo "$OK:OK: Average CPU load over $period minute(s) is $avg_load%, All is normal"
    fi
}

parse_arguments "$@"

# Collects CPU load
collect_cpu_load

# Periods to check
periods=("1" "5" "15")
warn_thresholds=($WARN_1_MIN $WARN_5_MIN $WARN_15_MIN)
crit_thresholds=($CRIT_1_MIN $CRIT_5_MIN $CRIT_15_MIN)

# Arrays to hold status messages and performance data
declare -a status_messages
declare -a performance_data

highest_status=$OK

for i in "${!periods[@]}"; do
    avg_load=$(calculate_average ${periods[$i]})
    result=$(check_thresholds $avg_load ${warn_thresholds[$i]} ${crit_thresholds[$i]} ${periods[$i]})
    status_code=$(echo $result | cut -d: -f1)
    message=$(echo $result | cut -d: -f2-)

    status_messages[$status_code]="${status_messages[$status_code]}$message\n"
    performance_data+=("cpu_load_${periods[$i]}min=$avg_load%;${warn_thresholds[$i]};${crit_thresholds[$i]};0;100")

    if [ $status_code -gt $highest_status ]; then
        highest_status=$status_code
    fi
done

# Prepare the final output
final_output=""

# Add the status messages to final output
for status_code in $(echo ${!status_messages[@]} | tr ' ' '\n' | sort -nr); do
    final_output+="${status_messages[$status_code]}"
done

# Add performance data to final output
final_output+="|"
for perf in "${performance_data[@]}"; do
    final_output+="$perf "
done

# Print the final output
echo -e "$final_output"

exit $highest_status
