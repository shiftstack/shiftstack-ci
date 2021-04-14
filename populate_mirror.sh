#!/bin/bash
# -*- coding: utf-8 -*-
# Copyright 2020 Red Hat, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#
# This script is a helper to populate a mirror registry
# for the installation of OpenShift in a restricted network
# (e.g. without internet access).
# It does what is documented here: https://tinyurl.com/y62uozsc
# Note: It assumes that the local container registry is connected to the
# mirror host, therefore to the Internet.
#
# Requirements:
# - a functional container image registry (e.g. docker-registry)
# - Internet access
# - 8 GB available for the registry (subject to change)
# - oc binary installed
# - auth file generated with valid credentials

set -e

if ! command -v oc &> /dev/null; then
    echo "oc binary not found, exiting ..."
    exit 1
fi

: ${OC_REGISTRY_AUTH_FILE:="auth.json"}
: ${TAG:="4.7.6-x86_64"}
: ${PRODUCT_REPO:="quay.io/openshift-release-dev"}
: ${RELEASE_NAME:="ocp-release"}
: ${INSECURE:="false"}

help() {
    echo "Populate a mirror registry for the installation of OpenShift in a restricted network"
    echo ""
    echo "Usage: ./populate_mirror.sh [options] -r myregistry.io"
    echo "Options:"
    echo "--auth          path of registry auth file, default: ${OC_REGISTRY_AUTH_FILE}"
    echo "-d, --debug     enable debug, default: false"
    echo "-h, --help      show this message"
    echo "-i, --insecure  do not verify TLS for mirror registry, default: ${INSECURE}"
    echo "-n, --name      release name, default (for production): ${RELEASE_NAME}"
    echo "-p, --product   product repository, including registry URL, default (for production): ${PRODUCT_REPO}"
    echo "-r, --registry  mirror registry URL, including namespace (required), e.g.: myregistry.io/foobar"
    echo "-t, --tag       openshift release tag, default: ${TAG}"
    echo ""
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            help
            exit 0
            ;;
        -d|--debug)
            set -o xtrace
            shift 1
            ;;
        -r|--registry)
            LOCAL_REGISTRY=$2
            shift 2
            ;;
        -t|--tag)
            TAG=$2
            shift 2
            ;;
        --auth)
            OC_REGISTRY_AUTH_FILE=$2
            shift 2
            ;;
        -p|--product)
            PRODUCT_REPO=$2
            shift 2
            ;;
        -n|--name)
            RELEASE_NAME=$2
            shift 2
            ;;
        -i|--insecure)
            INSECURE="true"
            shift 1
            ;;
        *)
            echo "$0: error - unexpected argument $1" >&2; help;
            exit 1
            ;;
    esac
done

if [ -z "$LOCAL_REGISTRY" ]; then
    echo "No mirror registry URL provided, exiting ..."
    exit 1
fi

if [ ! -f "$OC_REGISTRY_AUTH_FILE" ]; then
    echo "$OC_REGISTRY_AUTH_FILE not found, exiting ..."
    exit 1
fi

echo "Directly push the release images to the local registry:"
oc adm -a ${OC_REGISTRY_AUTH_FILE} release mirror --insecure=${INSECURE} \
     --from=${PRODUCT_REPO}/${RELEASE_NAME}:${TAG} \
     --to=${LOCAL_REGISTRY} \
     --to-release-image=${LOCAL_REGISTRY}:${TAG}

echo "Create the installation program that is based on the content:"
echo "that we mirrored, extract it and pin it to the release"
oc adm -a ${OC_REGISTRY_AUTH_FILE} release extract --insecure=${INSECURE} --command=openshift-install "${LOCAL_REGISTRY}:${TAG}"
echo "You now have ./openshift-install ready to be used."
