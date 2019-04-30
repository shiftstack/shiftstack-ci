# Ideally, we never have any bugs in cluster delete.
# However, even in this ideal scenario, we need
# protection from a patch under review breaking cluster delete
# and filling up our tenant with undeletable resources.
# In this case call the destroy script with `--force`

CONFIG=${CONFIG:-cluster_config.sh}
if [ ! -r "$CONFIG" ]; then
    echo "Could not find cluster configuration file."
    echo "Make sure $CONFIG file exists in the shiftstack-ci directory and that it is readable"
    exit 1
fi
source ./${CONFIG}

if [[ $1 == '--force' ]]; then
    echo Destroying cluster using openstack cli
    if [ -f $CLUSTER_NAME/metadata.json ]; then
        # elements created by the cluster are named $CLUSTER_NAME-hash by the installer
        CLUSTER_NAME=$(jq .infraID $CLUSTER_NAME/metadata.json | sed "s/\"//g")
    fi

    openstack server list -c ID -f value --name $CLUSTER_NAME | xargs --no-run-if-empty openstack server delete
    openstack router remove subnet  $CLUSTER_NAME-external-router $CLUSTER_NAME-service
    openstack router remove subnet  $CLUSTER_NAME-external-router $CLUSTER_NAME-nodes
    # delete interfaces from the router
    openstack network trunk list -c Name -f value | grep $CLUSTER_NAME | xargs --no-run-if-empty openstack network trunk delete
    openstack port list --network $CLUSTER_NAME-openshift -c ID -f value | xargs --no-run-if-empty openstack port delete

    # delete interfaces from the router
    PORT=$(openstack router show $CLUSTER_NAME-external-router -c interfaces_info -f value | cut -d '"' -f 12)
    openstack router remove port $CLUSTER_NAME-external-router $PORT


    openstack router unset --external-gateway $CLUSTER_NAME-external-router
    openstack router delete $CLUSTER_NAME-external-router

    openstack network delete $CLUSTER_NAME-openshift

    openstack security group delete $CLUSTER_NAME-api
    openstack security group delete $CLUSTER_NAME-master
    openstack security group delete $CLUSTER_NAME-worker


    for c in $(openstack container list -f value); do
        echo $c
        openstack container show $c | grep $CLUSTER_NAME
        if [ $? -eq 0 ]; then
            CONTAINER=$c
        fi
    done

    if [ ! -z "$CONTAINER" ]; then
        openstack object list -f value $CONTAINER | xargs --no-run-if-empty openstack object delete $CONTAINER
        openstack container delete $CONTAINER
    fi
else
    echo Destroying cluster using openshift-install
    $GOPATH/src/github.com/openshift/installer/bin/openshift-install --log-level=debug destroy cluster --dir $CLUSTER_NAME
fi
