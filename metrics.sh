#!/usr/bin/env bash

# This script prints quota information in the Prometheus Exposition Format.
# Requires $OS_CLOUD to be set to a value available in clouds.yaml.
#
# Depends on:
# * python3-openstackclient

set -Eeuo pipefail

os_project="$(openstack token issue -f value -c project_id)"

echo "# These metrics refer to project '$os_project' in the '$OS_CLOUD' cloud."
for service in 'compute' 'network'; do
	timestamp="$(date +"%s000")"
	openstack quota list --detail "--${service}" --project "$os_project" -f value -c 'Resource' -c 'In Use' -c 'Limit' \
		| sed -n \
			-e 's/^\(\w\+\)\s\([[:digit:]]\+\)\s\([[:digit:]]\+\)$/'"$service"'_\1{quota="inuse"} \2 '"$timestamp"'\n'"$service"'_\1{quota="limit"} \3 '"$timestamp"'/gp;' \
			-e 's/^\(\w\+\)\s\([[:digit:]]\+\)\s-1$/'"$service"'_\1{quota="inuse"} \2 '"$timestamp"'/gp'
done
