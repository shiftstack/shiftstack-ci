# Ideally, we never have any bugs in cluster delete.
# However, even in this ideal scenario, we need
# protection from a patch under review breaking cluster delete
# and filling up our tenant with undeletable resources.

# TODO(trown): make these arguments with basic validation
export OS_CLOUD=<PUT YOUR CLOUD HERE>
expoft CLUSTER_NAME=<THIS IS THE PREFIX USED ON ALL RESOURCES ie the * in *-master-0>

openstack server list -c ID -f value --name $CLUSTER_NAME | xargs openstack server delete

openstack router remove subnet  $CLUSTER_NAME-external-router $CLUSTER_NAME-service
openstack router remove subnet  $CLUSTER_NAME-external-router $CLUSTER_NAME-nodes
# delete interfaces from the router
openstack network trunk list -c Name -f value | grep $CLUSTER_NAME | xargs openstack network trunk delete
openstack port list --network $CLUSTER_NAME-openshift -c ID -f value | xargs openstack port delete

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
openstack object list -f value $CONTAINER | xargs openstack object delete $CONTAINER
openstack container delete $CONTAINER
