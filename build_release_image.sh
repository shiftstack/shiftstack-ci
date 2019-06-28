help() {
    echo "Build an Openshift Release Image"
    echo "Usage:                    build_release_image.sh [options] <Images> <quay.io username>"
    echo ""
    echo "Options:"
    echo "-h, --help                show this message"
    echo "-t, --tag <tag>           push to a custom tag in your origin release image repo, default: mco"
    echo ""
    echo "Images: you must include at least one"
    echo "-m, --mco                 build and push dependancies for mco to quay.io/<username>/image then"
    echo "                              build a release image from that repo."
    echo "-c, --capo [tag]          build a capo image locally, push it to quay.io/<username>/capo:[tag] then"
    echo "                              build a release image from that repo."
}

TAG="mco"
USERNAME=""
CAPO=""
MCO=""
set -x
# Parse Options
while :; do
    case $1 in
        -h| --help )
            help
            exit 0
            ;;
        -t | --tag )
            if [ -z "$2" ]; then
                echo "Error: tag option passed without a tag value. Please use -h, or --help to see usage"
                exit 1
            fi
            TAG=$2
            ;;
        -c | --capo )
            if [ -z "$2" ]; then
                CAPO="latest"
            elif [[ $2 =~ ^\-.*|^\-\-.* ]];then
                CAPO="latest"
            else
                CAPO="$2"
            fi
            ;;
        -m | --mco )
            MCO="true"
            ;;
        \? )
            printf 'WARN: Unknown option : %s\n' "$1" >&2
            exit 1
            ;;
        * )
            shift
            break
            ;;
    esac

    shift
done

if [ -z "$CAPO" ] && [ -z "$MCO" ];then
    echo "No images provided, can't build release image. Please use -h, or --help to see usage"
    exit 1
fi

if [ -z "$1" ]; then
    echo "No quay.io username provided, exiting ..."
    exit 1
else
    USERNAME=$1
fi

RELEASEIMAGE="
oc adm release new \
        --from-release="$FROM_IMAGE" \
        --to-image="$DEST_IMAGE" \
        --server https://api.ci.openshift.org \
        -n openshift"

export DEST_IMAGE="quay.io/$USERNAME/origin-release:$TAG"
export FROM_IMAGE="registry.svc.ci.openshift.org/origin/release:4.2"

if [ -n "$CAPO" ]
then
    capoRepo=quay.io/$USERNAME/capo:$CAPO
    pushd $GOPATH/src/sigs.k8s.io/cluster-api-provider-openstack
    podman build --no-cache -v $REPOS_DIR:/etc/yum.repos.d/:z -t $capoRepo .
    podman push $capoRepo
    popd

    RELEASEIMAGE="$RELEASEIMAGE \
    openstack-machine-controllers=$capoRepo"
fi

pushd $GOPATH/src/github.com/openshift/machine-config-operator

if [ -n "$MCO" ]
then

    for image in controller daemon operator server; do
        export WHAT=machine-config-$image
        ./hack/build-image.sh
    done

    for image in controller daemon operator server; do
        export WHAT=machine-config-$image
        export REPO="quay.io/$USERNAME"
        ./hack/push-image.sh
    done

    RELEASEIMAGE="$RELEASEIMAGE \
    machine-config-operator=quay.io/$USERNAME/origin-machine-config-operator \
    machine-config-controller=quay.io/$USERNAME/origin-machine-config-controller \
    machine-config-daemon=quay.io/$USERNAME/origin-machine-config-daemon \
    machine-config-server=quay.io/$USERNAME/origin-machine-config-server"
fi

$RELEASEIMAGE

popd
