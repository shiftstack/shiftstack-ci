#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ ! -r "$CONFIG" ]; then
    echo "Could not find cluster configuration file."
    echo "Make sure $CONFIG file exists in the shiftstack-ci directory and that it is readable"
    exit 1
fi
source ./${CONFIG}

case "$(openstack security group show -f value -c id default)" in
	ac891596-df7f-4533-9205-62c8f3976f46)
		>&2 echo 'Operating on MOC'
		;;
	1e7008c1-10f4-4d09-9d6e-d3de70b62eb6)
		>&2 echo 'Operating on VEXXHOST'
		;;
	*)
		>&2 echo "Refusing to run on anything else than the CI tenant"
		exit 1
esac

declare concurrently=false

while getopts c opt; do
	case "$opt" in
		c) concurrently=true ;;
		*) >&2 echo "Unknown flag: $opt"; exit 2 ;;
	esac
done

for cluster_id in $(./list-clusters -ls); do
	echo Destroying "$cluster_id"
	if [ "$concurrently" = true ]; then
		time ./destroy_cluster.sh -i "$cluster_id" &
	else
		time ./destroy_cluster.sh -i "$cluster_id"
	fi
done

# Clean leftover containers
openstack container list -f value -c Name |\
        grep -vf <(./list-clusters -a) |\
        xargs --no-run-if-empty openstack container delete -r

./stale -q volume snapshot | xargs --verbose --no-run-if-empty openstack volume snapshot delete
./stale -q volume | xargs --verbose --no-run-if-empty openstack volume delete
./stale -q floating ip | xargs --verbose --no-run-if-empty openstack floating ip delete