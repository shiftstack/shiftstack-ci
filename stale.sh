#!/usr/bin/env bash

set -Eeuo pipefail

unknown_command() {
	echo "Unknown command: $*"
	exit 1
}

print_help() {
	echo 'https://github.com/shiftstack/shiftstack-ci/blob/main/stale.sh'
	echo
	echo 'Prints the IDs of the stale resources, with the timestamp of the last update and the resource name.'
	echo
	echo 'Usage:'
	echo "$0 [-un|-q] <resource_type>"
	echo
	echo '"resource_type" can be any openstack resource type.'
	echo 'Resources are identified as stale if they were last updated more than 5 hours ago.'
	echo
	echo '-u  Only print the ID and the timestamp of the last update'
	echo '-n  Only print the ID and the resource name'
	echo '-q  Only print the ID'
	echo
	echo 'Examples:'
	echo "$0 port"
	echo "$0 -q floating ip"
}

declare \
	print_name=no \
	print_updated=no \
	quiet=no
while getopts nuqh o; do
	case "$o" in
		n) print_name=yes       ;;
		u) print_updated=yes    ;;
		q) quiet=yes            ;;
		h) print_help; exit     ;;
		*) unknown_command "$@" ;;
	esac
done
if [[ $print_name == 'yes' ]] || [[ $print_updated == 'yes' ]]; then
	if [[ $quiet == 'yes' ]]; then
		>&2 echo '-q can not be used with -n or -u.'
		exit 2
	fi
else
	if [[ $quiet != 'yes' ]]; then
		print_name=yes
		print_updated=yes
	fi
fi
shift $((OPTIND - 1))

declare -r resource_type="$*"

declare valid_limit
valid_limit="$(date --date='-5 hours' +%s)"
readonly valid_limit

list_server() {
	for resource_id in $(openstack server list -f value -c ID); do
		res="$(openstack server show -f json -c updated -c name "$resource_id")"
		update_time="$(jq -r '.updated' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
	done
}

list_port() {
	openstack port list -f json -c ID -c Name -c 'Updated At' \
		| jq -r '.[] | "\(.ID) \(."Updated At") \(.Name)"'
}

list_security_group() {
	for resource_id in $(openstack security group list -f value -c ID); do
		res="$(openstack security group show -f json -c updated_at -c name "$resource_id")"
		update_time="$(jq -r '.updated_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		# we can't and don't want to remove the default security group
		if [ "$name" != "default" ]; then
			printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
		fi
	done
}

list_loadbalancer() {
	declare rt="loadbalancer"
	for resource_id in $(openstack "$rt" list -f value -c id); do
		res="$(openstack "$rt" show -f json -c updated_at -c name "$resource_id")"
		update_time="$(jq -r '.updated_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
	done
}

list_generic() {
	declare rt="$1"
	for resource_id in $(openstack "$rt" list -f value -c ID); do
		res="$(openstack "$rt" show -f json -c updated_at -c name "$resource_id")"
		update_time="$(jq -r '.updated_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
	done
}

list_network() {
	for resource_id in $(openstack network list -f value -c ID); do
		# For networks we look at creation time, since removing a subnet updates the network
		res="$(openstack network show -f json -c created_at -c name "$resource_id")"
		creation_time="$(jq -r '.created_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		if [[ "$name" = *"hostonly"* ]] || [[ "$name" = *"external"* ]] || [[ "$name" = *"sahara-access"* ]] || [[ "$name" = *"public"* ]]; then
			continue
		fi
		printf '%s %s %s\n' "$resource_id" "$creation_time" "$name"
	done
}

list_subnet() {
	for resource_id in $(openstack subnet list -f value -c ID); do
		res="$(openstack subnet show -f json -c updated_at -c name "$resource_id")"
		update_time="$(jq -r '.updated_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		if [[ "$name" = *"hostonly"* ]] || [[ "$name" = *"external"* ]] || [[ "$name" = *"public"* ]]; then
			continue
		fi
		printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
	done
}

list_keypair() {
	for resource_id in $(openstack keypair list -f value -c Name); do
		res="$(openstack keypair show -f json -c created_at -c Name "$resource_id")"
		update_time="$(jq -r '.created_at' <<< "$res")"
		name="$(jq -r '.name' <<< "$res")"
		printf '%s %s %s\n' "$resource_id" "$update_time" "$name"
	done
}

case $resource_type in
	server)
		list_server ;;
	port)
		list_port ;;
	'router'|'network trunk'|'floating ip'|'volume'|'volume snapshot')
		list_generic "$resource_type" ;;
	'network')
		list_network;;
	'subnet')
		list_subnet;;
	'loadbalancer')
		list_loadbalancer ;;
	'security group')
		list_security_group ;;
	'keypair')
		list_keypair ;;
	'server group')
		>&2 printf 'Creation date is not available for %s.' "$resource_type"
		exit 3
		;;
	*)
		>&2 printf 'Resource "%s" not implemented.' "$resource_type"
		exit 3
		;;
esac | while read -r resource_id update_time name; do
	if [[ "$(date --date="$update_time" +%s)" -lt "$valid_limit" ]]; then
		printf '%s' "$resource_id"
		if [[ $print_updated == 'yes' ]]; then
			printf ' %s' "$update_time"
		fi
		if [[ $print_name == 'yes' ]]; then
			printf ' %s' "$name"
		fi
		printf '\n'
	fi
done
