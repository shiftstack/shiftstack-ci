#!/bin/bash

set -ex

eval "$(go env)"

pushd "$GOPATH/src/github.com/openshift/installer"
export MODE=dev
./hack/build.sh
popd
