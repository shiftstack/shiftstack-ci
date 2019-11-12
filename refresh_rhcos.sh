#!/usr/bin/env bash
set -eu
set -o pipefail

if [ -z "$OS_CLOUD" ]; then
    echo "Set your OS_CLOUD environment variable"
    exit 1
fi

BRANCH="4.2"

opts=$(getopt -n "$0"  -o "b:" --long "branch:"  -- "$@")

eval set --$opts

while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch)
            BRANCH=$2
            shift 2
            ;;

        *)
            break
            ;;
    esac
done

if [ $BRANCH == "4.2" ]; then
    REAL_BRANCH_NAME="release-$BRANCH"
    # We want to leave 4.2 image under the rhcos name
    IMAGE_NAME="rhcos"
elif [ $BRANCH == "4.3" ]; then
    REAL_BRANCH_NAME="release-$BRANCH"
    IMAGE_NAME="rhcos-$BRANCH"
else
    echo "Unknown branch $BRANCH"
    exit
fi

LOCAL_IMAGE_FILE=rhcos-latest.qcow2
RHCOS_VERSIONS_FILE=rhcos.json
curl --silent -o $RHCOS_VERSIONS_FILE https://raw.githubusercontent.com/openshift/installer/$REAL_BRANCH_NAME/data/data/rhcos.json

IMAGE_URL="$(jq --raw-output '.baseURI + .images.openstack.path' $RHCOS_VERSIONS_FILE)"
IMAGE_SHA="$(jq --raw-output '.images.openstack."uncompressed-sha256"' $RHCOS_VERSIONS_FILE)"
IMAGE_VERSION="$(jq --raw-output '."ostree-version"' $RHCOS_VERSIONS_FILE)"
rm $RHCOS_VERSIONS_FILE

if openstack image show -c properties -f json $IMAGE_NAME | grep -q "$IMAGE_VERSION"; then
    echo "RHCOS image already at the latest version $IMAGE_VERSION"
    exit
fi

echo "Downloading RHCOS image from:"
echo "$IMAGE_URL"

if [[ "$IMAGE_URL" == *.gz ]]; then
    curl --insecure --compressed -L -o ${LOCAL_IMAGE_FILE}.gz "$IMAGE_URL"
    gunzip -f ${LOCAL_IMAGE_FILE}.gz
else
    curl --insecure --compressed -L -o ${LOCAL_IMAGE_FILE} "$IMAGE_URL"
fi

echo "Verifying image..."
if ! sha256sum $LOCAL_IMAGE_FILE | grep -q $IMAGE_SHA; then
    echo Downloaded image is corrupted. Exiting...
    exit 1
fi

echo "Uploading image to ${OS_CLOUD} as $IMAGE_NAME-new"
openstack image create $IMAGE_NAME-new --container-format bare --disk-format qcow2 --file ${LOCAL_IMAGE_FILE} --private --property version=$IMAGE_VERSION

echo "Replace old $IMAGE_NAME image with new one on ${OS_CLOUD}"

# Always only keep one backup of rhcos image
openstack image delete $IMAGE_NAME-old || true

# Then swap the images
openstack image set --name $IMAGE_NAME-old $IMAGE_NAME || true
openstack image set --name $IMAGE_NAME $IMAGE_NAME-new

echo Done
