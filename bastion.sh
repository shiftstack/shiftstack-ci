#!/usr/bin/env bash

# Copyright 2021 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -Eeuo pipefail

print_help() {
	echo -e 'github.com/shiftstack/shiftstack-ci'
	echo -e 'Spin a bastion proxy on OpenStack'
	echo
	echo -e 'Usage to create the bastion:'
	echo -e "\t${0} -f <flavor> -i <image> -u <user> -e <external network> -k <key> CLUSTER-ID"
	echo
	echo -e 'Required parameters:'
	echo -e '\t-f\tFlavor of the bastion instance. Default to m1.tiny.'
	echo -e '\t-i\tImage of the bastion instance. Default to centos8-stream.'
	echo -e '\t-u\tUser of the bastion instance. Default to centos.'
	echo -e '\t-e\tName or ID of the public network where to create the floating IP. Default to external.'
	echo -e '\t-k\tName or ID of the SSH public key to add to the server.'
	echo -e '\tCLUSTER-ID: OpenShift Cluster ID.'
	echo
	echo -e 'Usage to delete the bastion:'
	echo -e "\t${0} -c CLUSTER-ID"
	echo
}

cleanup() {
	>&2 echo
	>&2 echo "Starting the cleanup for cluster ID $cluster_id"
	fip=$(openstack floating ip list -c "Floating IP Address" -f value --tags $cluster_id)
	openstack floating ip delete "$fip" || >&2 echo "Failed to delete FIP $fip"
	openstack server delete "$cluster_id" || >&2 echo "Failed to delete server $cluster_id"
	openstack router remove subnet "$cluster_id" "$cluster_id" || >&2 echo 'Failed to remove subnet from router'
	openstack router delete "$cluster_id" || >&2 echo "Failed to delete router $cluster_id"
	openstack subnet delete "$cluster_id" || >&2 echo "Failed to delete subnet $cluster_id"
	openstack network delete "$cluster_id" || >&2 echo "Failed to delete network $cluster_id"
	openstack security group delete "$cluster_id" || >&2 echo "Failed to delete security group $cluster_id"
	>&2 echo 'Cleanup done.'
}

unset http_proxy https_proxy
declare \
	server_flavor='m1.tiny' \
	server_image='centos8-stream' \
	server_user='centos' \
	key_name='' \
	external_network='external'
while getopts c:f:i:u:e:k:h opt; do
	case "$opt" in
		c) cluster_id="$2"; cleanup; exit 0 ;;
		f) server_flavor="$OPTARG"          ;;
		i) server_image="$OPTARG"           ;;
		i) server_user="$OPTARG"            ;;
		e) external_network="$OPTARG"       ;;
		k) key_name="$OPTARG"               ;;
		h) print_help; exit 0               ;;
		*) exit 1                           ;;
	esac
done
shift "$((OPTIND-1))"
declare -r name="bastion-${1:?This script requires one positional argument: the cluster ID}"
readonly \
	server_flavor \
	server_image  \
	key_name      \
	external_network

declare \
	sg_id=''      \
	network_id='' \
	subnet_id=''  \
	router_id=''  \
	server_id=''  \
	fip_id=''

retry() {
    local retries=$1
    local time=$2
    shift 2

    local count=0
    until "$@"; do
      exit=$?
      count=$(($count + 1))
      if [ $count -lt $retries ]; then
        sleep $time
      else
        return $exit
      fi
    done
    return 0
}

WORK_DIR=${WORK_DIR:-$(mktemp -d -t shiftstack-ci-XXXXXXXXXX)}

sg_id="$(openstack security group create -f value -c id "$name")"
>&2 echo "Created security group ${sg_id}"
openstack security group rule create --ingress --protocol tcp --dst-port 22 --description "${name} SSH" "$sg_id" >/dev/null
openstack security group rule create --ingress --protocol tcp --dst-port 3128 --description "${name} squid" "$sg_id" >/dev/null
openstack security group rule create --ingress --protocol icmp --description "${name} ingress ping" "$sg_id" >/dev/null
>&2 echo "Security group rules created ${sg_id}"

network_id="$(openstack network create -f value -c id "$name")"
>&2 echo "Created network ${network_id}"

subnet_id="$(openstack subnet create -f value -c id \
		--network "$network_id" \
		--subnet-range '172.16.0.0/24' \
		--dns-nameserver '1.1.1.1' \
		"$name")"
>&2 echo "Created subnet ${subnet_id}"

router_id="$(openstack router create -f value -c id \
		"$name")"
>&2 echo "Created router ${router_id}"
openstack router add subnet "$router_id" "$subnet_id"
openstack router set --external-gateway "$external_network" "$router_id"


server_id="$(openstack server create -f value -c id \
		--image "$server_image" \
		--flavor "$server_flavor" \
		--network "$network_id" \
		--security-group "$sg_id" \
		--key-name "$key_name" \
		"$name")"
>&2 echo "Created server ${server_id}"

fip_id="$(openstack floating ip create -f value -c floating_ip_address \
		--description "$name FIP" \
		--tag $name \
		"$external_network")"
>&2 echo "Created floating IP ${fip_id}"
>&2 openstack server add floating ip "$server_id" "$fip_id"

if ! retry 90 10 ssh $server_user@$fip_id uname -a >/dev/null; then
		echo "ERROR: Bastion is not reachable via its floating-IP: $fip_id"
		exit 1
fi

my_ip=$(curl https://icanhazip.com)
>&2 cat << EOF > $WORK_DIR/deploy_squid.sh
sudo dnf install -y squid
sudo bash -c "cat << EOF > /etc/squid/squid.conf
acl localnet src ${my_ip}/32
acl SSL_ports port 443
acl SSL_ports port 6443
acl Safe_ports port 80
acl Safe_ports port 6443
acl Safe_ports port 443
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localnet
http_access deny all
http_port 3128
EOF"
sudo systemctl start squid
EOF
scp $WORK_DIR/deploy_squid.sh $server_user@$fip_id:/tmp >/dev/null
ssh $server_user@$fip_id chmod +x /tmp/deploy_squid.sh >/dev/null
ssh $server_user@$fip_id bash -c /tmp/deploy_squid.sh >/dev/null
echo "Bastion proxy is ready!"
echo
echo "It can be used by exporting these variables:"
echo "  export http_proxy=http://$fip_id:3128"
echo "  export https_proxy=http://$fip_id:3128"
echo
