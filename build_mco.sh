help() {
    echo "Build an MCO Image"
    echo ""
    echo "Usage: ./build_mco.sh [options] <quay.io username>"
    echo "Options:"
    echo "-h        show this message"
    echo ""
}

export DEST_IMAGE="quay.io/$USERNAME/origin-release:mco"
export FROM_IMAGE="registry.svc.ci.openshift.org/origin/release:4.2"

# Parse Options
case $1 in
    -h|--help)
        help
        exit 0;;
    *);;
esac

if [ -z "$1" ]; then
    echo "No quay.io username provided, exiting ..."
    exit 1
fi

USERNAME="$1"
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

oc adm release new --from-release="$FROM_IMAGE" --server https://api.ci.openshift.org -n openshift --to-image="$DEST_IMAGE" machine-config-operator=quay.io/$USERNAME/origin-machine-config-operator:latest machine-config-controller=quay.io/$USERNAME/origin-machine-config-controller:latest machine-config-daemon=quay.io/$USERNAME/origin-machine-config-daemon:latest machine-config-server=quay.io/$USERNAME/origin-machine-config-server:latest
popd
