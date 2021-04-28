#!/usr/bin/env bash

set -Eeuo pipefail

# Requirements:
# * python-openstackclient
# * jq


print_help() {
	echo -e 'Run the CI cleanup, store logs and output a report.'
	echo
	echo -e 'Use:'
	echo -e "\t${0} [-o log_container -c cloud] [-m metrics_file] target_cloud..."
	echo
	echo -e 'Options:'
	echo -e "\t-o: The name of a Swift container where to store logs."
	echo -e "\t-c: The cloud where the Swift container for logs is situated."
	echo -e "\t-m: A file where to store metrics."
}

declare \
	log_cloud='' \
	log_container='' \
	metrics=/dev/null \
	log_file=/dev/stderr

while getopts c:o:m:h opt; do
	case "$opt" in
		c) log_cloud="$OPTARG"     ;;
		o) log_container="$OPTARG" ;;
		m) metrics="$OPTARG"       ;;
		h) print_help; exit 0      ;;
		*) print_help; exit 1      ;;
	esac
done
readonly log_cloud log_container metrics
shift $((OPTIND-1))

if [[ -n "$log_container" ]]; then
	if [[ -z "$log_cloud" ]]; then
		>&2 echo 'Log container (-o) set, but log cloud (-c) not set. Exiting.'
		exit 1
	fi
else
	>&2 echo "Log container (-o) not set. Redirecting logs to $log_file"
fi

increment() {
	declare -r \
		metrics_file="$1" \
		cloud="$2" \
		property="${3// /_}" \
		increment="${4:-1}"

	metric_name="${property}{cloud=\"${cloud}\"}"

	if ! grep -q "$metric_name" "$metrics_file"; then
		echo "${metric_name} ${increment}" >> "$metrics_file"
	else
		tmp_metrics=$(<"$metrics_file")
		search="\(${metric_name}\) \([0-9]\+\)"
		replace="printf '%s %s' '\1' \"\$((\2+${increment}))\""
		sed "s|${search}|${replace}|e" <<< "$tmp_metrics" > "$metrics_file"
	fi
}

to_metrics() {
	declare -r \
		metrics_file="$1" \
		cloud="$2"

	touch "$metrics_file"

	while IFS=$'\t' read -ra resource; do
		increment "$metrics_file" "$cloud" "${resource[0]}"
	done
}

for OS_CLOUD in "$@"; do
	if [[ -n "$log_container" ]]; then
		log_filename="clean-ci-log_$(date +'%s')_${OS_CLOUD}.txt"
		log_file="$(mktemp)"
	fi

	export OS_CLOUD
	./clean-ci-resources.sh 2> "$log_file" | to_metrics "$metrics" "$OS_CLOUD"

	if [[ -n "$log_container" ]]; then
		openstack --os-cloud="$log_cloud" object create -f value -c object --name "$log_filename" "$log_container" "$log_file"
		rm "$log_file"
	fi
done
