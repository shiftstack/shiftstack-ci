#!/usr/bin/env bash

set -Eeuo pipefail

unrecognised_command() {
	echo "Unrecognised command: $*"
	exit 1
}

print_help() {
	echo 'https://github.com/shiftstack/shiftstack-ci'
	echo
	echo 'list-clusters.sh [ -a | -s ] [ -l ]'
	echo
	echo 'Prints the IDs of the detected clusters, based on their Network.'
	echo
	echo -e '\t-a only lists active clusters'
	echo -e '\t-s only lists stale clusters'
	echo
	echo -e '\t-l prints the full cluster name. Otherwise, truncates at 14 characters'
	echo
	echo 'Clusters are identified as stale if their network is more than 5 hours old.'
}

print_cluster_id() {
	declare \
		cluster_id="$1" \
		format="$2"

	case "$format" in
		'long' ) echo "$cluster_id" ;;
		'short') echo "${cluster_id:0:14}" ;;
		*  ) >&2 echo "wrong format '$format'" ; exit 1 ;;
	esac
}

VALID_LIMIT="$(date --date='-7 hours' +%s)"
readonly VALID_LIMIT

declare filter=''
declare format='short'

while getopts lash o; do
	case "$o" in
		l) format='long'             ;;
		a) filter='active'           ;;
		s) filter='stale'            ;;
		h) print_help; exit          ;;
		*) unrecognised_command "$@" ;;
	esac
done

for network in $(openstack network list -c Name -f value); do
	if [[ $network = *-*-openshift ]] || [[ $network = *-*-network ]] && [[ $network != *"kuryr"* ]]; then
		declare CLUSTER_ID="$network"

		# IPI
		CLUSTER_ID="${CLUSTER_ID%-openshift}"
		# UPI
		CLUSTER_ID="${CLUSTER_ID%-network}"

		if [[ $network = *-*-byon* ]] || [[ $network = *-*-proxy* ]]; then
			# Find the real cluster ID for BYON
			CLUSTER_ID="${CLUSTER_ID%-proxy-bastion}"
			CLUSTER_ID="${CLUSTER_ID%-proxy-machines}"
			CLUSTER_ID="${CLUSTER_ID%-byon-machines}"
			CLUSTER_ID="$(openstack security group list -c Tags | grep "$CLUSTER_ID" | awk 'match($0, /openshiftClusterID=(\w+-\w+-\w+)/,m) {print m[1]}' | sort |uniq)"
		fi

		case "$filter" in
			'active')
				CREATION_TIME=$(openstack network show "$network" -c created_at -f value)
				CREATION_TIMESTAMP=$(date --date="$CREATION_TIME" +%s)
				if [[ "$CREATION_TIMESTAMP" -ge "$VALID_LIMIT" ]]; then
					print_cluster_id "$CLUSTER_ID" "$format"
				fi
				;;
			'stale')
				CREATION_TIME=$(openstack network show "$network" -c created_at -f value)
				CREATION_TIMESTAMP=$(date --date="$CREATION_TIME" +%s)
				if [[ "$CREATION_TIMESTAMP" -lt "$VALID_LIMIT" ]]; then
					print_cluster_id "$CLUSTER_ID" "$format"
				fi
				;;
			*)
				print_cluster_id "$CLUSTER_ID" "$format"
				;;
		esac
	fi
done
