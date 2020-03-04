#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ ! -r "$CONFIG" ]; then
    echo "Could not find cluster configuration file."
    echo "Make sure $CONFIG file exists in the shiftstack-ci directory and that it is readable"
    exit 1
fi
source ./${CONFIG}

if ! openstack security group show '8a1289c1-0584-453a-935c-9a3df67aef32' > /dev/null 2>&1;  then
    echo "Refusing to run on anything else than the CI tenant"
    exit
fi

for cluster_id in $(./list-clusters -ls); do
	echo Destroying "$cluster_id"
	time ./destroy_cluster.sh -i "$cluster_id"
done
