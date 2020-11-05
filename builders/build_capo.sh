#!/bin/bash

set -ex

help() {
    echo "Build a CAPO Image"
    echo ""
    echo "Usage: ./build_capo.sh [options] -u <quay.io username>"
    echo "Options:"
    echo "-h, --help      show this message"
    echo "-u, --username  registered username in quay.io"    
    echo "-t, --tag       push to a custom tag in your origin release image repo, default: capo"
    echo "-r, --release   openshift release version, default: 4.7"
    echo "-a, --auth      path of registry auth file, default: ./config.json"
    echo ""
}

: ${GOPATH:=${HOME}/go}
: ${TAG:="capo"}
: ${RELEASE:="4.7"}
: ${OC_REGISTRY_AUTH_FILE:="config.json"}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            help
            exit 0
            ;;
            
        -u|--username)
            USERNAME=$2
            shift 2
            ;;

        -t|--tag)
            TAG=$2
            shift 2
            ;;

        -r|--release)
            RELEASE=$2
            shift 2
            ;;

        -a|--auth)
            OC_REGISTRY_AUTH_FILE=$2
            shift 2
            ;;

        *)
            echo "Invalid option $1"
            help
            exit 0
            ;;
    esac
done

if [ -z "$USERNAME" ]; then
    echo "No quay username provided, exiting ..."
    exit 1
fi

if [ ! -f "$OC_REGISTRY_AUTH_FILE" ]; then
    echo "$OC_REGISTRY_AUTH_FILE not found, exiting ..."
    exit 1
fi

DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
FROM_IMAGE="registry.svc.ci.openshift.org/ocp/release:$RELEASE"
CAPO_IMAGE="quay.io/$USERNAME/capo:$TAG"

echo "Start building CAPO image $CAPO_IMAGE"

pushd $GOPATH/src/sigs.k8s.io/cluster-api-provider-openstack
podman build --no-cache -t $CAPO_IMAGE .
podman push $CAPO_IMAGE
popd

echo "$CAPO_IMAGE has been uploaded"

echo "Start building local release image"

oc adm release new \
    --registry-config="$OC_REGISTRY_AUTH_FILE" \
    --from-release="$FROM_IMAGE" \
    --to-file="origin-release.tar" \
    --server https://api.ci.openshift.org \
    -n openshift \
    openstack-machine-controllers=$CAPO_IMAGE

echo "Local release image is saved to $PWD/origin-release.tar"

podman import origin-release.tar $DEST_IMAGE

podman push $DEST_IMAGE

rm -f origin-release.tar

echo "Successfully pushed $DEST_IMAGE"
