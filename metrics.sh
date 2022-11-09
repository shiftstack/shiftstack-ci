#!/usr/bin/env bash

# This script prints quota information in the Prometheus Exposition Format.
# Requires $OS_CLOUD to be set to a value available in clouds.yaml.
#
# Depends on:
# * python3-openstackclient

set -Eeuo pipefail

os_project="$(openstack token issue -f value -c project_id)"

for service in 'compute' 'network'; do
	openstack quota list --detail "--${service}" --project "$os_project" -f value -c 'Resource' -c 'In Use' -c 'Limit' | while read -r resource inuse limit; do
		metric=openstack_quota_${service}_${resource}
		echo "# HELP ${metric} OpenStack project quota for ${service} ${resource}"
		echo "# TYPE ${metric} gauge"
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",type=\"inuse\"} $inuse"
		echo "${metric}{cloud=\"${OS_CLOUD}\",project=\"${os_project}\",type=\"limit\"} $limit"
	done
done
