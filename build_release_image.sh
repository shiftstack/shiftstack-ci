#!/bin/bash

set -e

help() {

    cat <<EOM
Build an Openshift Release Image"
Usage:                      build_release_image.sh [options] <quay.io username>

Options:
-h, --help                  show this message
-t, --tag <tag>             push to a custom tag in your origin release image repo, default: mco
-m, --mco                   build and push dependancies for mco to quay.io/<username>/image then
                                build a release image from that repo.
-c, --capo <ocp certs>      build a capo image locally, push it to quay.io/<username>/capo then
                                build a release image from that repo. You must pass the path to 
                                a directory containing upstream ocp certs as an argument.
EOM

    exit 2
}

TAG="custom"
USERNAME=""
MCO=""
CAPO=""

# Short Options
SHORT=(
    "h"
    "t:"
    "c:"
    "m"
)

# Long Options
LONG=(
    "help"
    "tag:"
    "capo:"
    "mco"
)

OPTS=$(getopt \
    --options "$(printf "%s" "${SHORT[@]}")" \
    --longoptions "$(printf "%s," "${LONG[@]}")" \
    --name "$(basename "$0")" \
    -- "$@"
)
eval set -- "$OPTS"

# Parse Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h| --help )  help;;
        -t | --tag )  TAG=$2; shift;;
        -c | --capo ) CAPO="$2"; shift;;
        -m | --mco )  MCO="true";;
        -- ) shift; break;;
    esac
    shift
done

if [ -z "$1" ]; then
    echo "Error: No quay.io username provided"
    exit 1
else
    USERNAME=$1
fi

FROM_IMAGE="registry.svc.ci.openshift.org/origin/release:4.2"
DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"

RELEASE_IMAGE="
oc adm release new \
        --from-release="$FROM_IMAGE" \
        --to-image="$DEST_IMAGE" \
        --server https://api.ci.openshift.org \
        -n openshift"

if [ -n "$CAPO" ]
then
    CAPO_REPO=quay.io/$USERNAME/capo
    pushd $GOPATH/src/sigs.k8s.io/cluster-api-provider-openstack
    podman build --no-cache -v $CAPO:/etc/yum.repos.d/:z -t $CAPO_REPO .
    podman push $CAPO_REPO
    popd

    RELEASE_IMAGE="$RELEASE_IMAGE \
    openstack-machine-controllers=$CAPO_REPO"
fi

if [ -n "$MCO" ]
then
    pushd $GOPATH/src/github.com/openshift/machine-config-operator
    for image in controller daemon operator server; do
        export WHAT=machine-config-$image
        ./hack/build-image.sh
    done

    for image in controller daemon operator server; do
        export WHAT=machine-config-$image
        export REPO="quay.io/$USERNAME"
        ./hack/push-image.sh
    done
    popd

    RELEASE_IMAGE="$RELEASE_IMAGE \
    machine-config-operator=quay.io/$USERNAME/origin-machine-config-operator:latest \
    machine-config-controller=quay.io/$USERNAME/origin-machine-config-controller:latest \
    machine-config-daemon=quay.io/$USERNAME/origin-machine-config-daemon:latest \
    machine-config-server=quay.io/$USERNAME/origin-machine-config-server:latest"
fi

$RELEASE_IMAGE
