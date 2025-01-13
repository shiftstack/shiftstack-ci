#!/usr/bin/env bash

set -Eeuo pipefail

# Usage:
# "$0" 4.12 ~/code/src/github.com/openshift/release

NEW_VERSION="$1"
PERIODICS_DIR="${2}/ci-operator/config/shiftstack/ci"

OLD_VERSION="4.$(( ${NEW_VERSION#4.} - 1 ))"
OLD_OLD_VERSION="4.$(( ${OLD_VERSION#4.} - 1 ))"

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
