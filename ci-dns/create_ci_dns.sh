#!/bin/bash
# TODO ci-dns VM must have the 128.31.27.48 FIP pointing to it
# TODO(trown): remove hardcoding of net-id
# TODO(mandre): need a ci-dns network
# openstack network show ci-dns
# +---------------------------+--------------------------------------+
# | Field                     | Value                                |
# +---------------------------+--------------------------------------+
# | admin_state_up            | UP                                   |
# | availability_zone_hints   |                                      |
# | availability_zones        | nova                                 |
# | created_at                | 2019-03-25T15:46:44Z                 |
# | description               |                                      |
# | dns_domain                | None                                 |
# | id                        | b978d863-7437-465d-86df-d1a5686f797f |
# | ipv4_address_scope        | None                                 |
# | ipv6_address_scope        | None                                 |
# | is_default                | None                                 |
# | is_vlan_transparent       | None                                 |
# | mtu                       | 9000                                 |
# | name                      | ci-dns                               |
# | port_security_enabled     | True                                 |
# | project_id                | 593227d1d5d04cba8847d5b6b742e0a7     |
# | provider:network_type     | None                                 |
# | provider:physical_network | None                                 |
# | provider:segmentation_id  | None                                 |
# | qos_policy_id             | None                                 |
# | revision_number           | 4                                    |
# | router:external           | Internal                             |
# | segments                  | None                                 |
# | shared                    | False                                |
# | status                    | ACTIVE                               |
# | subnets                   | 9402ba42-e92b-4db0-88ec-d42ac8f55039 |
# | tags                      |                                      |
# | updated_at                | 2019-03-25T15:46:44Z                 |
# +---------------------------+--------------------------------------+
#
# openstack subnet show 9402ba42-e92b-4db0-88ec-d42ac8f55039
# +-------------------+--------------------------------------+
# | Field             | Value                                |
# +-------------------+--------------------------------------+
# | allocation_pools  | 192.168.23.2-192.168.23.254          |
# | cidr              | 192.168.23.0/24                      |
# | created_at        | 2019-03-25T15:46:44Z                 |
# | description       |                                      |
# | dns_nameservers   |                                      |
# | enable_dhcp       | True                                 |
# | gateway_ip        | 192.168.23.1                         |
# | host_routes       |                                      |
# | id                | 9402ba42-e92b-4db0-88ec-d42ac8f55039 |
# | ip_version        | 4                                    |
# | ipv6_address_mode | None                                 |
# | ipv6_ra_mode      | None                                 |
# | name              | ci-dns                               |
# | network_id        | b978d863-7437-465d-86df-d1a5686f797f |
# | project_id        | 593227d1d5d04cba8847d5b6b742e0a7     |
# | revision_number   | 0                                    |
# | segment_id        | None                                 |
# | service_types     |                                      |
# | subnetpool_id     | None                                 |
# | tags              |                                      |
# | updated_at        | 2019-03-25T15:46:44Z                 |
# +-------------------+--------------------------------------+
#
# TODO(mandre): need a ci-dns security-group
# direction='ingress', ethertype='IPv4', port_range_max='53', port_range_min='53', protocol='udp', remote_ip_prefix='; 0.0.0.0/0'
# direction='ingress', ethertype='IPv4', port_range_max='53', port_range_min='53', protocol='tcp', remote_ip_prefix='; 0.0.0.0/0'
# direction='ingress', ethertype='IPv4', protocol='icmp', remote_ip_prefix='0.0.0.0/0'
# direction='egress', ethertype='IPv4'
# direction='ingress', ethertype='IPv4', port_range_max='22', port_range_min='22', protocol='tcp', remote_ip_prefix='; 0.0.0.0/0'
# direction='ingress', ethertype='IPv4', port_range_max='8080', port_range_min='8080', protocol='tcp', remote_ip_prefix='0.0.0.0/0'
# direction='egress', ethertype='IPv6'

# Transform yml to ign file using https://github.com/coreos/container-linux-config-transpiler

NAME=ci-dns

opts=$(getopt -n "$0" -o "n:" --long "name:"  -- "$@")

eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)
            NAME=$2
            shift 2
            ;;

        *)
            break
            ;;
    esac
done

ci_dns_net_id=$(openstack network show ci-dns -f value -c id)

openstack server create \
	--user-data ./CI-DNS.ign \
	--image rhcos \
	--flavor m1.s2.medium \
	--security-group default \
	--security-group ci-dns \
	--config-drive=true \
	--nic net-id=${ci_dns_net_id} \
	${NAME}
