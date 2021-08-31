#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "${1:-}" == '' ]]; then
	>&2 echo "Usage: $0 <job-url>"
	exit 1
fi

to_job_name() {
	trimmed_left="${1#*/origin-ci-test/}"
	printf '%s' "${trimmed_left%/artifacts/*}"
}

to_job_number() {
	name="$(to_job_name "$1")"
	trimmed_right="${name%/}"
	printf '%s' "${trimmed_right##*/}"

}

job_name="$(to_job_name "$1")"
job_number="$(to_job_number "$1")"

echo "Creating directory $job_number"
mkdir "$job_number"

echo "Syncing origin-ci-test/$job_name"
gsutil -m rsync -r "gs://origin-ci-test/${job_name}" "$job_number"
