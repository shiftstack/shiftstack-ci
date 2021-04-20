#!/usr/bin/env bash

set -Eeuo pipefail

# Requirements:
# * python-openstackclient
# * jq

if [ -z "$hook" ]; then
	>&2 echo 'Slack hook not defined as "$hook". Exiting.'
	exit 1
fi



declare logfile=/dev/null

for OS_CLOUD in 'moc-ci' 'vexxhost'; do
	if [ -d "$CI_CLEAN_LOG_DIR" ]; then
		logfilename="clean-ci-log_$(date +'%s')_${OS_CLOUD}.txt"
		logpath="${CI_CLEAN_LOG_DIR}/${logfilename}"

		if [ -n "$CI_CLEAN_LOG_URL" ]; then
			logurl="${CI_CLEAN_LOG_URL}/${logfilename}"
		fi
	fi
	export OS_CLOUD
	./clean-ci-resources.sh -j 2> "$logpath" \
		| jq '[to_entries[] | {(.key): (.value | length)}] | reduce .[] as $item ({}; .+$item)' \
		| sed 's|"|\\"|g' \
		| cat <(echo '{"text":"Stale resources on '"$OS_CLOUD"':\n```\n') - <(echo '```\n'"${logurl}"'"}') \
		| curl -sS -X POST -H 'Content-type: application/json' --data @- "$hook"
done
