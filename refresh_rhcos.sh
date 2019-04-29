#!/usr/bin/env bash
set -eu
set -o pipefail

if [ -z "$OS_CLOUD" ]; then
    echo "Set your OS_CLOUD environment variable"
    exit 1
fi

LOCAL_IMAGE_FILE=rhcos-latest.qcow2
RHCOS_VERSIONS_FILE=rhcos.json
curl --silent -o $RHCOS_VERSIONS_FILE https://raw.githubusercontent.com/openshift/installer/master/data/data/rhcos.json

IMAGE_URL="$(jq --raw-output '.baseURI + .images.openstack.path' $RHCOS_VERSIONS_FILE)"
IMAGE_SHA="$(jq --raw-output '.images.openstack."uncompressed-sha256"' $RHCOS_VERSIONS_FILE)"
IMAGE_VERSION="$(jq --raw-output '."ostree-version"' $RHCOS_VERSIONS_FILE)"
rm $RHCOS_VERSIONS_FILE

if openstack image show -c properties -f json rhcos | grep -q "$IMAGE_VERSION"; then
    echo "RHCOS image already at the latest version $IMAGE_VERSION"
    exit
fi

echo "Downloading RHCOS image from:"
echo "$IMAGE_URL"

curl --insecure --compressed -L -o ${LOCAL_IMAGE_FILE} "$IMAGE_URL" 

echo "Verifying image..."
if ! sha256sum $LOCAL_IMAGE_FILE | grep -q $IMAGE_SHA; then
    echo Downloaded image is corrupted. Exiting...
    exit 1
fi

# MOC doesn't provide disks larger than 10GB, this makes sure the image fits
# the disk
# Needs qemu-img version 2 or above
echo "Resizing image to fit a 10GB disk"
qemu-img resize ${LOCAL_IMAGE_FILE} --shrink 10G

echo "Uploading image to ${OS_CLOUD} as rhcos-new"
openstack image create rhcos-new --container-format bare --disk-format qcow2 --file ${LOCAL_IMAGE_FILE} --private --property version=$IMAGE_VERSION

echo "Replace old rhcos image with new one on ${OS_CLOUD}"

# Always only keep one backup of rhcos image
openstack image delete rhcos-old || true

# Then swap the images
openstack image set --name rhcos-old rhcos || true
openstack image set --name rhcos rhcos-new

echo Done
