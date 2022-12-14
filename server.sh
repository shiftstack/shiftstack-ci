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
	CLEANUP_CODE=0

	for fip_id in "${fips_id[@]}"; do
		if ! openstack floating ip delete "$fip_id"; then
			>&2 echo "Failed to delete FIP $fip_id"
			CLEANUP_CODE=1
		fi
	done
	if [ -n "$server_id" ]; then
		if ! openstack server delete --wait "$server_id"; then
			>&2 echo "Failed to delete server $server_id"
			CLEANUP_CODE=1
		fi
	fi
	if [ -n "$vol_id" ]; then
		if ! openstack volume delete "$vol_id"; then
			>&2 echo "Failed to delete volume $vol_id"
			CLEANUP_CODE=1
		fi
	fi
	if [ -n "$port_id" ]; then
		if ! openstack port delete "$port_id"; then
			>&2 echo "Failed to delete port $port_id"
			CLEANUP_CODE=1
		fi
	fi
	if [ -n "$router_id" ]; then
		if ! openstack router remove subnet "$router_id" "$subnet_id"; then
			>&2 echo 'Failed to remove subnet from router'
			CLEANUP_CODE=1
		fi
		if ! openstack router delete "$router_id"; then
			>&2 echo "Failed to delete router $router_id"
			CLEANUP_CODE=1
		fi
	fi
	if [ -n "$sg_id" ]; then
		if ! openstack security group delete "$sg_id"; then
			>&2 echo "Failed to delete security group $sg_id"
			CLEANUP_CODE=1
		fi
	fi
	for lb_id in "${lb_ids[@]}"; do
		if ! openstack loadbalancer delete --cascade --wait "$lb_id"; then
			>&2 echo "Failed to delete loadbalancer $lb_id"
			CLEANUP_CODE=1
		fi
	done
	if [ -n "$network_id" ]; then
		if ! openstack network delete "$network_id"; then
			>&2 echo "Failed to delete network $network_id"
			CLEANUP_CODE=1
		fi
	fi

	if [ "$CLEANUP_CODE" == 1 ]; then
		>&2 echo 'Cleanup finished with errors'
		exit 1
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
openstack loadbalancer delete --cascade --wait "$lb_id" || >&2 echo "Failed to delete loadbalancer $lb_id"
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

declare -A drivers=( ["ovn"]="SOURCE_IP_PORT" ["amphora"]="ROUND_ROBIN")
declare -A ports=( ["ovn"]="ovn-lb-vip" ["amphora"]="octavia-lb")
declare -a fips_id
declare -a lb_ids

for driver in "${!drivers[@]}"; do
	lb_id="$(openstack loadbalancer create --wait --name "$name" --provider "$driver" -f value -c id --vip-subnet-id "$subnet_id")"
	>&2 echo "Created loadbalancer ${lb_id}"
	lb_ids+=("${lb_id}")

	lb_listener_id="$(openstack loadbalancer listener create --wait --name "$name" -f value -c id --protocol TCP --protocol-port 22 "$lb_id")"
	>&2 echo "Created loadbalancer listener ${lb_listener_id}"

	lb_pool_id="$(openstack loadbalancer pool create --wait --name "$name" -f value -c id --lb-algorithm "${drivers[$driver]}" --listener "$lb_listener_id" --protocol TCP)"
	>&2 echo "Created loadbalancer pool ${lb_pool_id}"

	lb_member_id="$(openstack loadbalancer member create --wait -f value -c id --subnet-id "$subnet_id" --address "$server_ip" --protocol-port 22 "$lb_pool_id")"
	>&2 echo "Created loadbalancer member ${lb_member_id}"

	fip_id="$(openstack floating ip create -f value -c id \
			--description "$name" \
			"$external_network")"
	fip_address="$(openstack floating ip show -f value -c floating_ip_address "$fip_id")"
	>&2 echo "Created floating IP ${fip_id}: ${fip_address}"
	fips_id+=("${fip_id}")
	lb_vip_id="$(openstack port show -f value -c id "${ports[$driver]}"-"$lb_id")"
	openstack floating ip set --port "$lb_vip_id" "$fip_id"

	if [ "$os_user" != '' ]; then
		echo "Testing connectivity from the instance ${name}"
		sleep 60
		if ! ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no "$os_user"@"$fip_address" ping -c 1 1.1.1.1; then
			echo "Error when running a ping from the instance. Dumping load balancer status..."
			openstack loadbalancer status show "$lb_id"
			echo "Error when running a ping from the instance. Dumping instance console..."
			openstack console log show "$name" || true
			echo "Done"
			exit 1
		fi
	fi
done

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
