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

export DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
export FROM_IMAGE="registry.svc.ci.openshift.org/origin/release:4.2"

pushd $GOPATH/src/github.com/openshift/machine-config-operator
export WHAT=machine-config-operator
export REPO="quay.io/$USERNAME"
./hack/build-image
./hack/push-image.sh

oc adm release new \
    --from-release="$FROM_IMAGE" \
    --to-image="$DEST_IMAGE" \
    --server https://api.ci.openshift.org \
    -n openshift \
    machine-config-operator=quay.io/$USERNAME/origin-machine-config-operator:latest
popd
