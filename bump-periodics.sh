#!/usr/bin/env bash

set -Eeuo pipefail

# Usage:
# "$0" 5.0 ~/code/src/github.com/openshift/release
#
# When bumping across a major version boundary (e.g. 4.x -> 5.0), update
# LAST_MINOR below with the last minor release of the previous major.

NEW_VERSION="$1"
PERIODICS_DIR="${2}/ci-operator/config/shiftstack/ci"

# Last minor version of each major (for major-version boundary bumps)
declare -A LAST_MINOR=( [4]=22 )

prev_version() {
    local major minor prev_major
    IFS='.' read -r major minor <<< "$1"
    if (( minor > 0 )); then
        echo "${major}.$(( minor - 1 ))"
    else
        prev_major=$(( major - 1 ))
        echo "${prev_major}.${LAST_MINOR[${prev_major}]}"
    fi
}

OLD_VERSION="$(prev_version "${NEW_VERSION}")"
OLD_OLD_VERSION="$(prev_version "${OLD_VERSION}")"

OLD_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${OLD_VERSION}.yaml"
NEW_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${NEW_VERSION}.yaml"

OLD_TP_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${OLD_VERSION}__techpreview.yaml"
NEW_TP_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${NEW_VERSION}__techpreview.yaml"

OLD_UPGRADE_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${OLD_VERSION}__upgrade-from-stable-${OLD_OLD_VERSION}.yaml"
NEW_UPGRADE_PERIODIC="${PERIODICS_DIR}/shiftstack-ci-release-${NEW_VERSION}__upgrade-from-stable-${OLD_VERSION}.yaml"

# Pointing development branch to `ci` stream, while maintenance branches point
# to `nightly` to reduce the noise

cp "${OLD_PERIODIC}" "${NEW_PERIODIC}"
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/" "${NEW_PERIODIC}"
sed -i "s/stream: nightly/stream: ci/" "${NEW_PERIODIC}"
sed -i "s/stream: ci/stream: nightly/" "${OLD_PERIODIC}"

cp "${OLD_TP_PERIODIC}" "${NEW_TP_PERIODIC}"
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/" "${NEW_TP_PERIODIC}"
sed -i "s/stream: nightly/stream: ci/" "${NEW_TP_PERIODIC}"
sed -i "s/stream: ci/stream: nightly/" "${OLD_TP_PERIODIC}"

cp "${OLD_UPGRADE_PERIODIC}" "${NEW_UPGRADE_PERIODIC}"
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/" "${NEW_UPGRADE_PERIODIC}"
sed -i "s/${OLD_OLD_VERSION}/${OLD_VERSION}/" "${NEW_UPGRADE_PERIODIC}"
sed -i "s/stream: nightly/stream: ci/" "${NEW_UPGRADE_PERIODIC}"
sed -i "s/stream: ci/stream: nightly/" "${OLD_UPGRADE_PERIODIC}"

echo "Done. Now go to '${2}' and run a good 'make update' before pushing the patch."
echo "Do not forget to manually add slack notification to the job definition."
