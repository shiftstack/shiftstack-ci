#!/usr/bin/env bash

set -Eeuo pipefail

# Requirements:
# * python-openstackclient
# * jq


print_help() {
	echo -e 'Run the CI cleanup, store logs and output a report.'
	echo
	echo -e 'Use:'
	echo -e "\t${0} -k slack_hook [-o log_container -c cloud] target_cloud..."
	echo
	echo -e 'Required configuration:'
	echo -e "\t-k: A Slack hook."
	echo
	echo -e 'Options:'
	echo -e "\t-o: The name of a Swift container where to store logs."
	echo -e "\t-c: The cloud where the Swift container for logs is situated."
	echo
	echo -e "Examples:"
	echo -e "\t${0} -k <slack_hook> -c <cloud> -o <log_container> <target_cloud_1> <target_cloud_2>..."
}

declare \
	slack_hook='' \
	log_cloud='' \
	log_container=''

while getopts k:c:o:h o; do
	case "$o" in
		k) slack_hook="$OPTARG" ;;
		c) log_cloud="$OPTARG" ;;
		o) log_container="$OPTARG" ;;
		h) print_help; exit 0 ;;
		*) print_help; exit 1 ;;
	esac
done
readonly slack_hook log_cloud log_container
shift $((OPTIND-1))

if [[ -z "$slack_hook" ]]; then
	>&2 echo 'Slack hook (-k) not set. Exiting.'
	exit 1
fi

declare log_file=/dev/null
if [[ -n "$log_container" ]]; then
	if [[ -z "$log_cloud" ]]; then
		>&2 echo 'Log container (-o) set, but log cloud (-c) not set. Exiting.'
		exit 1
	fi
	container_base_url="$(openstack catalog show --os-cloud="${log_cloud}" -f json object-store | jq -r '.endpoints[] | select(.interface=="public").url')"
else
	>&2 echo "Log container (-o) not set. Redirecting logs to $log_file"
fi

for OS_CLOUD in "$@"; do
	if [[ -n "$log_container" ]]; then
		log_filename="clean-ci-log_$(date +'%s')_${OS_CLOUD}.txt"
		log_url="${container_base_url}/${log_container}/${log_filename}"
		log_file="$(mktemp)"
	fi

	export OS_CLOUD
	./clean-ci-resources.sh -j 2> "$log_file" \
		| jq '[to_entries[] | {(.key): (.value | length)}] | reduce .[] as $item ({}; .+$item)' \
		| sed 's|"|\\"|g' \
		| cat <(printf '{"text":"Stale resources on %s:\\n```\\n' "$OS_CLOUD") - <(printf '```\\n%s"}' "$log_url") \
		| curl -sS -X POST -H 'Content-type: application/json' --data @- "$slack_hook"

	if [[ -n "$log_container" ]]; then
		openstack --os-cloud="$log_cloud" object create -f value -c object --name "$log_filename" "$log_container" "$log_file"
		rm "$log_file"
	fi
done
