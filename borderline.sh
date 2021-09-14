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

: "${min_percentage:="15"}"
: "${failed:="0"}"
project_id=$(openstack token issue -f value -c project_id)

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

check_quotas() {
    service=$1
    echo "Checking quotas for ${service}:"
    while IFS= read -r line;do
        metric_name=$(echo "$line" | awk '{ print $1 }')
        metric_inuse=$(echo "$line" | awk '{ print $2 }')
        metric_reserved=$(echo "$line" | awk '{ print $3 }')
        metric_limit=$(echo "$line" | awk '{ print $4 }')
        if [[ "$metric_limit" -eq 0 ]]; then
            echo "  No quotas set for ${metric_name}"
            continue
        fi
        if [[ "$metric_limit" -eq -1 ]]; then
            echo "  Unlimited quotas for ${metric_name}"
            continue
        fi
        ((metric_available=metric_limit-metric_reserved-metric_inuse))
        ((percentage_value=metric_available*100/metric_limit))
        if [[ "$percentage_value" -eq 0 ]]; then
            echo "  CRITICAL: No more resource available for ${metric_name}"
            failed=1
        elif [[ "$percentage_value" -lt "$min_percentage" ]]; then
            echo "  WARNING: Only $percentage_value% of $metric_name are available"
            failed=1
        else
            echo "  Available resources for ${metric_name}: ${percentage_value}%"
        fi
    done < <(openstack quota list --detail --"$service" --project "${project_id}" -f value)
}

check_quotas compute
check_quotas network

if [[ "$failed" -eq 1 ]]; then
    echo "Some resources have less than ${min_percentage}% available, actions should be taken!"
    exit 11
fi

echo "No issue found, all resources have at least ${min_percentage}% of the total available"
