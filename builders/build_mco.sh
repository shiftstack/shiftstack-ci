#!/bin/bash

help() {
    echo "Build an MCO Image"
    echo ""
    echo "Usage: ./build_mco.sh [options] <quay.io username>"
    echo "Options:"
    echo "-h, --help      show this message"
    echo "-r, --release   openshift release version, default: 4.11"
    echo "-t, --tag       push to a custom tag in your origin release image repo, default: mco"
    echo ""
}

TAG="mco"

: "${RELEASE:="4.11"}"

# Parse Options
case $1 in
    -h|--help)
        help
        exit 0;;
    -r|--release)
        RELEASE=$2
        shift 2
        ;;
    -t|--tag)
        TAG=$2
        shift 2
        ;;
    *);;
esac

if [ -z "$1" ]; then
    echo "No quay.io username provided, exiting ..."
    exit 1
fi

USERNAME="$1"

DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
FROM_IMAGE="registry.ci.openshift.org/origin/release:$RELEASE"
MCO_IMAGE=quay.io/$USERNAME/machine-config-operator:$TAG

pushd "$GOPATH"/src/github.com/openshift/machine-config-operator || exit
podman build --no-cache -t "$MCO_IMAGE" .
podman push "$MCO_IMAGE"

oc adm release new \
    --from-release="$FROM_IMAGE" \
    --include=rhel-coreos-8 rhel-coreos-8=registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest \
    --to-image="$DEST_IMAGE" \
    --server https://api.ci.openshift.org \
    -n openshift \
    machine-config-operator="$MCO_IMAGE"
popd || exit
