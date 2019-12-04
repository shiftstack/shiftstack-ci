#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ ! -r "$CONFIG" ]; then
    echo "Could not find cluster configuration file."
    echo "Make sure $CONFIG file exists in the shiftstack-ci directory and that it is readable"
    exit 1
fi
source ./${CONFIG}

if ! openstack floating ip show 128.31.27.48 > /dev/null 2>&1;  then
    echo "Refusing to run on anything else than the CI tenant"
    exit
fi

VALID_LIMIT=$(date --date='-5 hours' +%s)

for network in $(openstack network list -c Name -f value); do
    if [[ $network == *-*-openshift ]]; then
        CREATION_TIME=$(openstack network show $network -c created_at -f value)
        CREATION_TIMESTAMP=$(date --date="$CREATION_TIME" +%s)
        if [[ $CREATION_TIMESTAMP < $VALID_LIMIT ]]; then
            CLUSTER_ID=${network/-openshift/}
            echo Destroying $CLUSTER_ID
            time ./destroy_cluster.sh -i $CLUSTER_ID
        fi
    fi
done
