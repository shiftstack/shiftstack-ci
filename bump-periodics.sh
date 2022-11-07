#!/usr/bin/env bash

set -Eeuo pipefail

# Usage:
# "$0" 4.12 ~/code/src/github.com/openshift/release

NEW_VERSION="$1"
PERIODICS_DIR="${2}/ci-operator/config/shiftstack/shiftstack-ci"

OLD_VERSION="4.$(( ${NEW_VERSION#4.} - 1 ))"
OLD_OLD_VERSION="4.$(( ${OLD_VERSION#4.} - 1 ))"
OUT_OF_SUPPORT_VERSION="4.$(( ${OLD_VERSION#4.} - 5 ))"

OLD_PERIODIC="${PERIODICS_DIR}/shiftstack-shiftstack-ci-main__periodic-${OLD_VERSION}.yaml"
NEW_PERIODIC="${PERIODICS_DIR}/shiftstack-shiftstack-ci-main__periodic-${NEW_VERSION}.yaml"
OUT_OF_SUPPORT_PERIODIC="${PERIODICS_DIR}/shiftstack-shiftstack-ci-main__periodic-${OUT_OF_SUPPORT_VERSION}.yaml"

OLD_UPGRADE_PERIODIC="${PERIODICS_DIR}/shiftstack-shiftstack-ci-main__periodic-${OLD_VERSION}-upgrade-from-stable-${OLD_OLD_VERSION}.yaml"
NEW_UPGRADE_PERIODIC="${PERIODICS_DIR}/shiftstack-shiftstack-ci-main__periodic-${NEW_VERSION}-upgrade-from-stable-${OLD_VERSION}.yaml"

# Copy-paste "simple install" periodics
# shellcheck disable=SC2016 # Shellcheck appears confused by the proliferation of quotes
yq --yaml-output '.
	# Replace the old version in base images (.base_images.*.name)
	| ( .base_images[] | select(.name == "'"${OLD_VERSION}"'") | .name ) |= "'"${NEW_VERSION}"'"

	# Replace the old version in release images (.releases.{initial,latest}.{prerelease,candidate}.version)
	| ( .releases[][] | select(.version == "'"${OLD_VERSION}"'") | .version ) |= "'"${NEW_VERSION}"'"

	# Ensure that the release stream is set to "ci"
	| ( .releases[][] | select(.stream == "nightly") | .stream ) |= "ci"

	# Replace the version in the footer generated metadata, just to be on the safe side
	# (although it will probably be rewritten when running `make update`
	| .zz_generated_metadata.variant="periodic-'"${NEW_VERSION}"'"

	' "$OLD_PERIODIC" > "$NEW_PERIODIC"

# Copy-paste "upgrade" periodics
# shellcheck disable=SC2016 # Shellcheck appears confused by the proliferation of quotes
yq --yaml-output '.
	# Replace the old version in base images (.base_images.*.name)
	| ( .base_images[] | select(.name == "'"${OLD_VERSION}"'") | .name ) |= "'"${NEW_VERSION}"'"

	# Replace the previous starting version in base images (.base_images.*.name)
	| ( .base_images[] | select(.name == "'"${OLD_OLD_VERSION}"'") | .name ) |= "'"${OLD_VERSION}"'"

	# Replace the old version in release images (.releases.*.*.version)
	| ( .releases[][] | select(.version == "'"${OLD_VERSION}"'") | .version ) |= "'"${NEW_VERSION}"'"

	# Replace the previous starting version release images (.releases.*.*.version_bounds.lower)
	| ( .releases[][] | select(.version_bounds != null) | .version_bounds.lower ) |= "'"${OLD_VERSION}.0-0"'"

	# Replace the old version release images (.releases.*.*.version_bounds.upper)
	| ( .releases[][] | select(.version_bounds != null) | .version_bounds.upper ) |= "'"${NEW_VERSION}.0-0"'"

	# Replace the version in the footer generated metadata, just to be on the safe side
	# (although it will probably be rewritten when running `make update`
	| .zz_generated_metadata.variant="periodic-'"${NEW_VERSION}"'-upgrade-from-stable-'"${OLD_VERSION}"'"

	' "$OLD_UPGRADE_PERIODIC" > "$NEW_UPGRADE_PERIODIC"

# Set all intervals to 72h for the branch that is not the newest any more
yq --yaml-output --in-place '.
	# Set the release stream to "nightly" to reduce noise on maintenance branches
	| ( .releases[][] | select(.stream == "ci") | .stream ) |= "nightly"

	# Set a conveniently long interval to all tests in the old periodics
	| del(.tests[].interval)
	| del(.tests[].cron)
	| .tests[].minimum_interval |= "72h"

	' "$OLD_PERIODIC"

# Set maximum interval for branch that fell off support
yq --yaml-output --in-place '.
	# Set a conveniently long interval to all tests in the old periodics
	| del(.tests[].interval)
	| del(.tests[].cron)
	| .tests[].minimum_interval |= "8766h"

	' "$OUT_OF_SUPPORT_PERIODIC"

echo "Done. Now go to '${2}' and run a good 'make update' before pushing the patch."
