#!/usr/bin/env bash

set -Eeuo pipefail

# * Creates application credentials for all clouds in the available clouds.yaml
# * Outputs them in the format consumable by the Ansible playbook:
#    { "clouds": [{ "name": "<cloud name>", "auth_url": "", "credential_id": "", "credential_secret": ""}]}
for cloud in "$@"; do
	openstack --os-cloud "$cloud" application credential create shiftstack-bot -f json -c id -c secret \
		| jq '{"credential_id": .id, "credential_secret": .secret} + {"name": "'"$cloud"'"}' \
		| jq '.+{"auth_url": "'"$(openstack --os-cloud "$cloud" catalog show identity -f json | jq -r '.endpoints[] | select(.interface=="public").url + "/v3"')"'"}'
done | jq -sc '. | {"clouds": .}'
