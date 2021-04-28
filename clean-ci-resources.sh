#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ -r "$CONFIG" ]; then
	source ./${CONFIG}
fi

case "$(openstack security group show -f value -c id default)" in
	ac891596-df7f-4533-9205-62c8f3976f46)
		>&2 echo 'Operating on MOC'
		;;
	1e7008c1-10f4-4d09-9d6e-d3de70b62eb6)
		>&2 echo 'Operating on VEXXHOST'
		;;
	*)
		>&2 echo "Refusing to run on anything else than the CI tenant"
		exit 1
esac

declare \
	concurrently=false \
	json=false

while getopts cj opt; do
	case "$opt" in
		c) concurrently=true ;;
		j) json=true ;;
		*) >&2 echo "Unknown flag: $opt"; exit 2 ;;
	esac
done

resultfile="$(mktemp)"
trap 'rm $resultfile' EXIT

if [ "$json" = true ]; then
	cat > $resultfile <<< '{}'
fi

report() {
	declare \
		result='' \
		resource_type="$*"

	while read -r resource_id; do
		if [ "$json" = true ]; then
			result=$(jq ".\"$resource_type\" += [\"$resource_id\"]" "$resultfile")
		else
			result="$(printf '%s\t%s' "$resource_type" "$resource_id" | cat "$resultfile" - )"
		fi
		cat > "$resultfile" <<< "$result"
		echo "$resource_id"
	done
}

for cluster_id in $(./list-clusters -ls); do
	if [ "$concurrently" = true ]; then
		time ./destroy_cluster.sh -i "$(echo "$cluster_id" | report cluster)" >&2 &
	else
		time ./destroy_cluster.sh -i "$(echo "$cluster_id" | report cluster)" >&2
	fi
done

# Clean leftover containers
openstack container list -f value -c Name \
	| grep -vf <(./list-clusters -a) \
	| report container \
	| xargs --verbose --no-run-if-empty openstack container delete -r \
	>&2

for resource in 'volume snapshot' 'volume' 'floating ip'; do
	# shellcheck disable=SC2086
	./stale -q $resource | report $resource | xargs --verbose --no-run-if-empty openstack $resource delete >&2
done

cat "$resultfile"
