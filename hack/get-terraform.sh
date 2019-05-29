#!/bin/sh

have() {
	command -v "${@}" >/dev/null 2>/dev/null
}


OS=linux
ARCH=amd64
FUNZIP="${FUNZIP:-funzip}"
if ! have "${FUNZIP}"
then
	if have gunzip
	then
		FUNZIP=gunzip
	else
		command -V "${FUNZIP}"
		exit 1
	fi
fi &&
if have go
then
	OS="$(go env GOOS)" &&
	ARCH="$(go env GOARCH)"
fi &&

# TODO get versions from openshift-installer toml files
TERRAFORM_VERSION="0.12.0-rc1" &&
TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip" &&
echo "pulling ${TERRAFORM_URL}" >&2 &&
cd "$(go env GOPATH)" &&
mkdir -p bin &&
curl -L "${TERRAFORM_URL}" | "${FUNZIP}" >bin/terraform &&
chmod +x bin/terraform

go get -d github.com/terraform-providers/terraform-provider-openstack/
cd "$(go env GOPATH)/src/github.com/terraform-providers/terraform-provider-openstack/"
git checkout b1406b8e4894faad993aff786f0bb50bfec8e281
go get github.com/terraform-providers/terraform-provider-openstack/
