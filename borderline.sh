#!/usr/bin/env bash

help() {
    echo "Report borderline usage of resources"
    echo ""
    echo "Usage: ./borderline.sh [options]"
    echo "Options:"
    echo "-h, --help            show this message"
    echo "-m, --min-percentage  define the minimum percentage of available resources (default: 15%)"    
    echo ""
}

: ${min_percentage:="15"}
: ${failed:="0"}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help
            exit 0
            ;;
        -m|--min-percentage)
            min_percentage=$2
            shift 2
            ;;
        *)
            echo "Invalid option $1"
            help
            exit 0
            ;;
    esac
done

declare -A limits
while IFS= read -r line;do
    metric_name=$(echo "$line" | awk '{ print $1 }')
    metric_val=$(echo "$line" | awk '{ print $2 }')
    limits+=(["$metric_name"]="$metric_val")
done < <(openstack limits show --absolute -f value)

for res in "${!limits[@]}"; do
    # we only want to capture resources that have a "used" metric,
    # and start by "total".
    [[ $res = total* ]] || continue
    res=${res#"total"}
    res=${res%"Used"}
    # API snowflakes...
    if [[ "$res" == "RAM" ]]; then
        max_name="maxTotalRAMSize"
    elif [[ "$res" == "SecurityGroups" || "$res" == "ServerGroups" || "$res" == "Gigabytes" ]]; then
        max_name="max${res}"
    elif [[ "$res" == "Gigabytes" ]]; then
        continue
    else
        max_name="maxTotal${res}"
    fi
    max_value=${limits[$max_name]}
    if [[ -z "$max_value" ]]; then
        continue
    fi
    used_name="total${res}Used"
    used_value=${limits[$used_name]}
    # In OpenStack, -1 means unlimited quotas (e.g. no limit)
    if [[ "$max_value" == -1 ]]; then
        continue
    fi
    ((available_value=$max_value-$used_value))
    ((percentage_value=$available_value*100/$max_value))
    if [[ "$percentage_value" -lt "$min_percentage" ]]; then
        echo "WARNING: Only $percentage_value% of $res are available"
        failed=1
    fi
done

if [[ "$failed" -eq 1 ]]; then
    exit 1
fi
