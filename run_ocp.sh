#!/usr/bin/env bash

set -x
set -e

source "${CONFIG}"

# check whether we have a free floating IP
FLOATING_IP=$(openstack floating ip list --status DOWN --format value | awk -F ' ' 'NR==1 {print $2}')

# create new floating ip if doesn't exist
if [ -z "$FLOATING_IP" ]; then
    FLOATING_IP=$(openstack floating ip create $OPENSTACK_EXTERNAL_NETWORK --format value --column floating_ip_address)
fi

# add data to /etc/hosts
grep -qxF "$FLOATING_IP $API_ADDRESS" /etc/hosts || echo "$FLOATING_IP $API_ADDRESS" | sudo tee -a /etc/hosts
grep -qxF "$FLOATING_IP $CONSOLE_ADDRESS" /etc/hosts || echo "$FLOATING_IP $CONSOLE_ADDRESS" | sudo tee -a /etc/hosts
grep -qxF "$FLOATING_IP $AUTH_ADDRESS" /etc/hosts || echo "$FLOATING_IP $AUTH_ADDRESS" | sudo tee -a /etc/hosts

if [ ! -d $CLUSTER_NAME ]; then
    mkdir -p $CLUSTER_NAME
fi

if [ ! -f $CLUSTER_NAME/install-config.yaml ]; then
    export CLUSTER_ID=$(uuidgen --random)
    cat > $CLUSTER_NAME/install-config.yaml << EOF
apiVersion: v1beta3
baseDomain: ${BASE_DOMAIN}
clusterID:  ${CLUSTER_ID}
machines:
- name:     master
  replicas: 2
- name:     worker
  replicas: 1
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr:             10.128.0.0/14
    hostSubnetLength: 9
  serviceCIDR: 172.30.0.0/16
  machineCIDR: 10.0.0.0/16
  type:        OpenshiftSDN
platform:
  openstack:
    cloud:            ${OS_CLOUD}
    externalNetwork:  ${OPENSTACK_EXTERNAL_NETWORK}
    region:           ${OPENSTACK_REGION}
    computeFlavor:    ${OPENSTACK_FLAVOR}
    lbFloatingIP:     ${FLOATING_IP}
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
fi


$GOPATH/src/github.com/openshift/installer/bin/openshift-install --log-level=debug ${1:-create} ${2:-cluster} --dir $CLUSTER_NAME
