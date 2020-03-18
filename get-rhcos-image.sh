#!/usr/bin/env bash
set -eu
set -o pipefail
BRANCH=master
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--branch)
            BRANCH=$2
            shift 2
            ;;
        -g|--gunzip)
            GUNZIP=true
            shift
            ;;
        -i|--info)
            INFO=true
            shift
            ;;
        -f|--outputfile)
            OUTPUTFILE=$2
            shift 2
            ;;
        *)
            break
            ;;
    esac
done
IMAGE_NAME="rhcos-$BRANCH"
if [ $BRANCH == "master" ]; then
    REAL_BRANCH_NAME="master"
else
    REAL_BRANCH_NAME="release-$BRANCH"
fi

IMAGE_SOURCE=https://raw.githubusercontent.com/openshift/installer/${REAL_BRANCH_NAME}/data/data/rhcos.json

echo "Looking for $REAL_BRANCH_NAME in $IMAGE_SOURCE"
set +e
IMAGE_URL="$(curl --silent $IMAGE_SOURCE | jq --raw-output '.baseURI + .images.openstack.path')"
if [ $? -ne 0 ]; then
    echo "Failed to find $REAL_BRANCH_NAME"
    exit 1
fi
set -e
echo "RHCOS for $REAL_BRANCH_NAME available at:"
echo "$IMAGE_URL"

if [[ ! -z ${INFO+x} ]]; then
    exit 0
fi

echo "Downloading RHCOS image for $REAL_BRANCH_NAME"
curl --insecure --compressed -L -O "$IMAGE_URL"

IMAGE_NAME=$(echo "${IMAGE_URL##*/}")

if [ ! -z ${GUNZIP+x} ]; then
    gzip -l $IMAGE_NAME >/dev/null 2>&1
    # Lets check to see if file is compressed with gzip
    # and uncompress it if so
    if [[ $? -eq 0 ]]
    then
        echo "$IMAGE_NAME is compressed. Expanding..."
        gunzip -f $IMAGE_NAME
        IMAGE_NAME="${IMAGE_NAME%.gz}"
    fi
fi

# Save image with user specified name.
if [[ ! -z ${OUTPUTFILE+x} ]]; then
   mv $IMAGE_NAME ${OUTPUTFILE}
   IMAGE_NAME=${OUTPUTFILE}
fi
echo File saved as $IMAGE_NAME
