help() {
    echo "Build an MCO Image"
    echo ""
    echo "Usage: ./build_mco.sh [options] <quay.io username>"
    echo "Options:"
    echo "-h, --help      show this message"
    echo "-t, --tag       push to a custom tag in your origin release image repo, default: mco"
    echo ""
}

TAG="mco"

# Parse Options
case $1 in
    -h|--help)
        help
        exit 0;;
    -t|--tag)
        TAG=$2
        shift
        shift;;
    *);;
esac

if [ -z "$1" ]; then
    echo "No quay.io username provided, exiting ..."
    exit 1
fi

USERNAME="$1"

DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
FROM_IMAGE="registry.ci.openshift.org/origin/release:4.2"
MCO_IMAGE=quay.io/$USERNAME/machine-config-operator:$TAG

pushd $GOPATH/src/github.com/openshift/machine-config-operator
podman build --no-cache -t $MCO_IMAGE .
podman push $MCO_IMAGE

oc adm release new \
    --from-release="$FROM_IMAGE" \
    --to-image="$DEST_IMAGE" \
    --server https://api.ci.openshift.org \
    -n openshift \
    machine-config-operator=$MCO_IMAGE
popd
