#!/usr/bin/env bash
# This script returns the ssh keys of the approvers of a given team name in the
# OWNERS_ALIASES file of a given project.
# The script will return 1 if the script fails to curl the OWNER_ALIASES file
# or if the yq command is not found.

set -Eeuo pipefail

GITHUB_PROJECT="${GITHUB_PROJECT:-openshift/installer}"
TEAM_NAME="${TEAM_NAME:-openstack-approvers}"

if ! command -v yq &> /dev/null; then
    echo "yq could not be found"
    echo "https://github.com/mikefarah/yq"
    exit 1
fi

OWNER_ALIASES=$(curl -s "https://raw.githubusercontent.com/${GITHUB_PROJECT}/master/OWNERS_ALIASES")
if [ -z "$OWNER_ALIASES" ]; then
    echo "Failed to curl the OWNER_ALIASES from ${GITHUB_PROJECT}"
    exit 1
fi

# shellcheck disable=SC2016
MEMBERS=$(yq -r '.aliases[env(TEAM_NAME)] | join(" ")' <<< "$OWNER_ALIASES")

for member in $MEMBERS; do
    key=$(curl -s "https://github.com/$member.keys")
    printf '# %s\n%s\n\n' "$member" "$key"
done
