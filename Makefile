
KEY_NAME ?= $(shell whoami)

shiftstack-bot: bot/cloud-credentials.json
	ansible-playbook -i bot/inventory.yaml bot/clean-ci-resources.yaml
.PHONY: shiftstack-bot

bot/cloud-credentials.json:
	bot/openstack-credentials.sh vexxhost moc-ci moc psi > $@

server:
	OS_CLOUD=psi ./server.sh -f ci.m1.micro -i Fedora-Cloud-Base-33 -e provider_net_shared_3 -k $(KEY_NAME) -p shiftstack-bot
.PHONY: server
