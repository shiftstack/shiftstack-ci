#!/bin/bash
# The script will attempt to delete the openstack
# resources used by a cluster with given infra-id from
# the cloud provider pointed to by OS_CLOUD

opts=$(getopt -n "$0"  -o "o:i:" --long "os-cloud:,infra-id:"  -- "$@")


eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--os-cloud)
            OS_CLOUD=$2
            export OS_CLOUD
            shift 2
            ;;
        -i|--infra-id)
            INFRA_ID=$2
            shift 2
            ;;
        *)
            break
            ;;
    esac
done


if [ -z "$INFRA_ID" ]; then
    echo "Could not find infrastructure id."
    echo "You may specify it with -i|--infra-id option to the script."
    exit 1
fi

if [ -z "$OS_CLOUD" ]; then
   echo "Could not find OS_CLOUD"
   echo "You may either define it using exprot OS_CLOUD= or specify it with -o|--os_cloud option"
   exit 1
fi


echo Destroying $INFRA_ID cluster using openstack cli on $OS_CLOUD.

openstack server list -c ID -f value --name $INFRA_ID | xargs --no-run-if-empty openstack server delete
openstack router remove subnet  $INFRA_ID-external-router $INFRA_ID-service
openstack router remove subnet  $INFRA_ID-external-router $INFRA_ID-nodes
# delete interfaces from the router
openstack network trunk list -c Name -f value | grep $INFRA_ID | xargs --no-run-if-empty openstack network trunk delete
openstack port list --network $INFRA_ID-openshift -c ID -f value | xargs --no-run-if-empty openstack port delete

# delete interfaces from the router
PORT=$(openstack router show $INFRA_ID-external-router -c interfaces_info -f value | cut -d '"' -f 12)
if [ -n "$PORT" ]; then
    openstack router remove port $INFRA_ID-external-router $PORT
fi

openstack router unset --external-gateway $INFRA_ID-external-router
openstack router delete $INFRA_ID-external-router

# IPI network
openstack network delete $INFRA_ID-openshift

# UPI network
openstack network delete $INFRA_ID-network

openstack security group delete $INFRA_ID-api
openstack security group delete $INFRA_ID-master
openstack security group delete $INFRA_ID-worker

openstack server group delete $INFRA_ID-master

for c in $(openstack container list -f value); do
    echo $c
    openstack container show $c | grep $INFRA_ID
    if [ $? -eq 0 ]; then
        CONTAINER=$c
    fi
done

if [ ! -z "$CONTAINER" ]; then
    openstack object list -f value $CONTAINER | xargs --no-run-if-empty openstack object delete $CONTAINER
    openstack container delete $CONTAINER
fi
