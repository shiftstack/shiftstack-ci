#!/usr/bin/env bash

# Copyright 2020 Red Hat, Inc.
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
	echo -e 'Spin a server on OpenStack'
	echo
	echo -e 'Usage:'
	echo -e "\t${0} [-p] -f <flavor> -i <image> -e <external network> -k <key> NAME"
	echo
	echo -e 'Required parameters:'
	echo -e '\t-f\tFlavor of the Compute instance.'
	echo -e '\t-i\tImage of the Compute instance.'
	echo -e '\t-e\tName or ID of the public network where to create the floating IP.'
	echo -e '\t-k\tName or ID of the SSH public key to add to the server.'
	echo -e '\tNAME: name to give to the OpenStack resources.'
	echo
	echo -e 'Optional parameters:'
	echo -e '\t-d\tRun the script in debug mode'
	echo -e '\t-p\tDo not clean up the server after creation'
	echo -e '\t\t(will print a cleanup script instead of executing it).'
	echo -e '\t-u\tTest connectivity from the instance by setting the cloud user from the image (e.g. centos)'
	echo -e '\t-t\tRun the script without pause (create/cleanup)'
}

declare \
	debug=''         \
	persistent=''    \
	interactive=''   \
	os_user=''       \
	server_flavor='' \
	server_image=''  \
	key_name=''      \
	external_network='external'
while getopts dtpf:u:i:e:k:h opt; do
	case "$opt" in
		d) debug='yes'                ;;
		p) persistent='yes'           ;;
		t) interactive='no'           ;;
		u) os_user="$OPTARG"          ;;
		f) server_flavor="$OPTARG"    ;;
		i) server_image="$OPTARG"     ;;
		e) external_network="$OPTARG" ;;
		k) key_name="$OPTARG"         ;;
		h) print_help; exit 0         ;;
		*) exit 1                     ;;
	esac
done

if [ "$debug" == 'yes' ]; then
	set -x
fi

shift "$((OPTIND-1))"
declare -r name="${1:?This script requires one positional argument: the resource name}"
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
	port_id=''    \
	server_id=''  \
	lb_member_id='' \
	lb_pool_id='' \
	lb_listener_id='' \
	lb_id='' \
	fip_id=''

cleanup() {
	>&2 echo
	>&2 echo
	>&2 echo 'Starting the cleanup...'
	if [ -n "$fip_id" ]; then
		openstack floating ip delete "$fip_id" || >&2 echo "Failed to delete FIP $fip_id"
	fi
	if [ -n "$server_id" ]; then
		openstack server delete --wait "$server_id" || >&2 echo "Failed to delete server $server_id"
	fi
	if [ -n "$vol_id" ]; then
		openstack volume delete "$vol_id" || >&2 echo "Failed to delete volume $vol_id"
	fi
	if [ -n "$port_id" ]; then
		openstack port delete "$port_id" || >&2 echo "Failed to delete port $port_id"
	fi
	if [ -n "$router_id" ]; then
		openstack router remove subnet "$router_id" "$subnet_id" || >&2 echo 'Failed to remove subnet from router'
		openstack router delete "$router_id" || >&2 echo "Failed to delete router $router_id"
	fi
	if [ -n "$sg_id" ]; then
		openstack security group delete "$sg_id" || >&2 echo "Failed to delete security group $sg_id"
	fi
	if [ -n "$lb_member_id" ]; then
		openstack loadbalancer member delete "$lb_pool_id" "$lb_member_id" || >&2 echo "Failed to delete loadbalancer member $lb_member_id from pool $lb_pool_id"
	fi
	if [ -n "$lb_pool_id" ]; then
		openstack loadbalancer pool delete "$lb_pool_id" || >&2 echo "Failed to delete loadbalancer pool $lb_pool_id"
	fi
	if [ -n "$lb_listener_id" ]; then
		openstack loadbalancer listener delete "$lb_listener_id" || >&2 echo "Failed to delete loadbalancer listener $lb_listener_id"
	fi
	if [ -n "$lb_id" ]; then
		openstack loadbalancer delete "$lb_id" || >&2 echo "Failed to delete loadbalancer $lb_id"
	fi
	if [ -n "$subnet_id" ]; then
		openstack subnet delete "$subnet_id" || >&2 echo "Failed to delete subnet $subnet_id"
	fi
	if [ -n "$network_id" ]; then
		openstack network delete "$network_id" || >&2 echo "Failed to delete network $network_id"
	fi
	>&2 echo 'Cleanup done.'
}

trap cleanup EXIT

print_cleanup_script() {
	cat <<EOF
# Below the instructions to undo.
openstack floating ip delete "$fip_id" || >&2 echo "Failed to delete FIP $fip_id"
openstack server delete --wait "$server_id" || >&2 echo "Failed to delete server $server_id"
openstack volume delete "$vol_id" || >&2 echo "Failed to delete volume $vol_id"
openstack port delete "$port_id" || >&2 echo "Failed to delete port $port_id"
openstack router remove subnet "$router_id" "$subnet_id" || >&2 echo 'Failed to remove subnet from router'
openstack router delete "$router_id" || >&2 echo "Failed to delete router $router_id"
openstack security group delete "$sg_id" || >&2 echo "Failed to delete security group $sg_id"
openstack loadbalancer member delete "$lb_pool_id" "$lb_member_id" || >&2 echo "Failed to delete loadbalancer member $lb_member_id from pool $lb_pool_id"
openstack loadbalancer pool delete "$lb_pool_id" || >&2 echo "Failed to delete loadbalancer pool $lb_pool_id"
openstack loadbalancer listener delete "$lb_listener_id" || >&2 echo "Failed to delete loadbalancer listener $lb_listener_id"
openstack loadbalancer delete "$lb_id" || >&2 echo "Failed to delete loadbalancer $lb_id"
openstack subnet delete "$subnet_id" || >&2 echo "Failed to delete subnet $subnet_id"
openstack network delete "$network_id" || >&2 echo "Failed to delete network $network_id"
EOF

}

vol_id="$(openstack volume create --size 10 -f value -c id "$name")"
>&2 echo "Created volume ${vol_id}"

sg_id="$(openstack security group create -f value -c id "$name")"
>&2 echo "Created security group ${sg_id}"
openstack security group rule create --ingress --protocol tcp  --dst-port 22 --description "${name} SSH" "$sg_id" >/dev/null
openstack security group rule create --ingress --protocol icmp               --description "${name} ingress ping" "$sg_id" >/dev/null
openstack security group rule create --ingress --protocol tcp  --dst-port 80 --description "${name} ingress HTTP" "$sg_id" >/dev/null
>&2 echo 'Security group rules created.'

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

port_id="$(openstack port create -f value -c id \
		--network "$network_id" \
		--security-group "$sg_id" \
		"$name")"
>&2 echo "Created port ${port_id}"

server_id="$(openstack server create --wait -f value -c id \
		--block-device uuid="$vol_id" \
		--image "$server_image" \
		--flavor "$server_flavor" \
		--nic "port-id=$port_id" \
		--security-group "$sg_id" \
		--key-name "$key_name" \
		"$name")"
# shellcheck disable=SC2086
server_id="$(echo $server_id | tr -d '\r')"
>&2 echo "Created server ${server_id}"
server_ip="$(openstack server show "$server_id" -c addresses -f json | grep -Pom 1 '[0-9.]{7,15}')"

lb_id="$(openstack loadbalancer create --name "$name" --provider ovn -f value -c id --vip-subnet-id "$subnet_id")"
>&2 echo "Created loadbalancer ${lb_id}"

lb_listener_id="$(openstack loadbalancer listener create --name "$name" -f value -c id --protocol TCP --protocol-port 22 "$lb_id")"
>&2 echo "Created loadbalancer listener ${lb_listener_id}"

lb_pool_id="$(openstack loadbalancer pool create --name "$name" -f value -c id --lb-algorithm SOURCE_IP_PORT --listener "$lb_listener_id" --protocol TCP)"
>&2 echo "Created loadbalancer pool ${lb_pool_id}"

lb_member_id="$(openstack loadbalancer member create -f value -c id --subnet-id "$subnet_id" --address "$server_ip" --protocol-port 22 "$lb_pool_id")"

fip_id="$(openstack floating ip create -f value -c id \
		--description "$name" \
		"$external_network")"
fip_address="$(openstack floating ip show -f value -c floating_ip_address "$fip_id")"
>&2 echo "Created floating IP ${fip_id}: ${fip_address}"
lb_vip_id="$(openstack port show -f value -c id ovn-lb-vip-"$lb_id")"
openstack floating ip set --port "$lb_vip_id" "$fip_id"

if [ "$os_user" != '' ]; then
	echo "Testing connectivity from the instance ${name}"
	if ! ssh "$os_user"@"$fip_address" ping -c 1 1.1.1.1; then
		echo "Error when running a ping from the instance..."
		exit 1
	fi
fi

if [ "$persistent" == 'yes' ]; then
	>&2 echo "Server created."
	trap true EXIT
	print_cleanup_script
else
	if [ "$interactive" != 'no' ]; then
		>&2 echo "Server created. Press ENTER to tear down."
		# shellcheck disable=SC2162,SC2034
		read pause
	fi
fi
