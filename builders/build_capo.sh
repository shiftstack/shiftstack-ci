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
: ${OPENSTACK_RELEASE:="train"}
: ${CAPO_DIR:=""}

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
    echo "-u/--username was not provided, exiting ..."
    exit 1
fi

if [ ! -f "$OC_REGISTRY_AUTH_FILE" ]; then
    echo "$OC_REGISTRY_AUTH_FILE not found, exiting ..."
    exit 1
fi

DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
FROM_IMAGE="registry.ci.openshift.org/origin/release:$RELEASE"
CAPO_IMAGE="quay.io/$USERNAME/capo:$TAG"

echo "Start building CAPO image $CAPO_IMAGE"

if [ -z "$CAPO_DIR" ]; then
    # Go returns an error like "no Go files" but the repo is actually cloned.
    go get github.com/openshift/cluster-api-provider-openstack || true
    CAPO_DIR=$GOPATH/src/github.com/openshift/cluster-api-provider-openstack
else
    if [ ! -d "$CAPO_DIR" ]; then
        echo "$CAPO_DIR does not exist, exiting ..."
        exit 1
    fi
    echo "$CAPO_DIR will be used to build CAPO"
fi

pushd $CAPO_DIR
REPOS_DIR=$(mktemp -d -t build-origin-XXXXXXXXXX)
curl https://raw.githubusercontent.com/openshift/release/master/core-services/release-controller/_repos/ocp-$RELEASE-default.repo -o $REPOS_DIR/ocp-$RELEASE-default.repo
curl https://github.com/openshift/shared-secrets/blob/master/mirror/ops-mirror.pem -o $REPOS_DIR/ops-mirror.pem
curl https://raw.githubusercontent.com/openshift/installer/master/images/openstack/rdo-$OPENSTACK_RELEASE.repo -o $REPOS_DIR/openstack.repo
podman build --no-cache -v $REPOS_DIR:/etc/yum.repos.d/:z -v $REPOS_DIR/ops-mirror.pem:/tmp/key/ops-mirror.pem:z -t $CAPO_IMAGE .
rm -rf $REPOS_DIR
podman push $CAPO_IMAGE
popd

echo "$CAPO_IMAGE has been uploaded"

echo "Start building local release image"

oc adm release new \
    --registry-config="$OC_REGISTRY_AUTH_FILE" \
    --from-release="$FROM_IMAGE" \
    --server https://api.ci.openshift.org \
    --to-image $DEST_IMAGE \
    openstack-machine-controllers=$CAPO_IMAGE

echo "Successfully pushed $DEST_IMAGE"

echo "Testing release image"
podman pull $DEST_IMAGE
if ! podman run --rm $DEST_IMAGE image openstack-machine-controllers >/dev/null; then
    echo "$DEST_IMAGE is not usable, something went wrong, exiting ..."
    exit 1
fi
echo "$DEST_IMAGE image was tested, you can now deploy with the following command:"
echo "OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=$DEST_IMAGE openshift-install create cluster (...)"
