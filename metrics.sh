#!/usr/bin/env bash

# This script prints quota information in the Prometheus Exposition Format.
# Requires $OS_CLOUD to be set to a value available in clouds.yaml.
#
# Depends on:
# * python3-openstackclient

set -Eeuo pipefail

os_project="$(openstack token issue -f value -c project_id)"

for service in 'compute' 'network'; do
	openstack quota list --detail "--${service}" --project "$os_project" -f value -c 'Resource' -c 'In Use' -c 'Reserved' -c 'Limit' | while read -r resource inuse reserved limit; do
		metric=openstack_quota_${service}_${resource}

                # A limit of -1 means no limit. +Inf should make more sense in
                # arithmetic operations than -1.
                [ "${limit}" == "-1" ] && limit="+Inf"

		echo "# HELP ${metric} OpenStack project quota for ${service} ${resource}"
		echo "# TYPE ${metric} gauge"
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",type=\"inuse\"} $inuse"
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",type=\"reserved\"} $reserved"
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",type=\"limit\"} $limit"
	done
done


metric=openstack_server
echo "# HELP ${metric} OpenStack servers by status"
echo "# TYPE ${metric} gauge"
openstack server list -f value -c Status \
	| uniq -c \
	| while read -r number state; do
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",status=\"${state}\"} $number";
	done
