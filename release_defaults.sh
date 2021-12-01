#!/bin/bash

scriptdir=${scriptdir:-.}

function get_release_image() (
    version=latest
    if [ "$OPENSHIFT_RELEASE" != "nightly" ]; then
        version="$version-$OPENSHIFT_RELEASE"
    fi

    curl -s "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp-dev-preview/$version/release.txt" |
           awk '/^Pull From:/ {print $3}'
)

function mktmpdir() (
    tmpdir="$scriptdir/tmp"
    mkdir -p "$tmpdir"
    echo "$tmpdir"
)

function pull_secret_file() (
    tmpdir=$(mktmpdir)
    pull_secret_file="$tmpdir/pull-secret.json"

    if [ ! -f "$pull_secret_file" ]; then
        echo "$PULL_SECRET" > "$pull_secret_file"
    fi

    echo "$pull_secret_file"
)

if [ -n "$OPENSHIFT_RELEASE" ]; then
    release_image=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-$(get_release_image "$OPENSHIFT_RELEASE")}

    # Obtain OPENSHIFT_INSTALLER from the specified release unless we've
    # overridden it.
    if [ -z "$OPENSHIFT_INSTALLER" ]; then
        tmpdir=$(mktmpdir)
        pull_secret_file=$(pull_secret_file)

        echo "Downloading openshift-install for $release_image"
        oc adm release extract --registry-config="$pull_secret_file" \
            --to="$tmpdir" --from="$release_image" \
            --command=openshift-install --command-os=linux
        OPENSHIFT_INSTALLER="$tmpdir/openshift-install"

    # We've overridden the release installer. Set
    # OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE so we still install the
    # requested version using the overridden installer
    else
        export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE:-$release_image}
    fi
fi

OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-$(go env GOPATH)/src/github.com/openshift/installer/bin/openshift-install}

if [ -n "$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE" ]; then
    echo "Using overridden release image $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE"
    release_image="$OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE"
else
    echo "Querying $OPENSHIFT_INSTALLER for default release image"

    # Query the installer for its release image
    release_image=$("$OPENSHIFT_INSTALLER" version | awk '/^release image/ {print $3}')

    echo "Using default installer release image $release_image"
fi

echo "Fetching release info for $release_image"
pull_secret_file=$(pull_secret_file)
release_version=$(oc adm release info --registry-config="$pull_secret_file" "$release_image" |
                  awk '/^\s*Version:\s/ {print $2}')
echo "Release has version $release_version"

version_bash=$(echo "$release_version" | awk '{
                if (match($0, /([0-9]+\.[0-9]+)\.([0-9]+)-/, groups) == 0)
                    exit 1;
                print "OPENSHIFT_RELEASE_MAJOR="groups[1]"\nOPENSHIFT_RELEASE_MINOR="groups[2]
            }')
eval "$version_bash"
echo "Release has major version $OPENSHIFT_RELEASE_MAJOR, minor version $OPENSHIFT_RELEASE_MINOR"
