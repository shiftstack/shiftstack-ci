#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ -r "$CONFIG" ]; then
	# shellcheck disable=SC1090
	source "./${CONFIG}"
fi

case "$(openstack security group show -f value -c id default)" in
	ac891596-df7f-4533-9205-62c8f3976f46)
		>&2 echo 'Operating on MOC'
		;;
	1e7008c1-10f4-4d09-9d6e-d3de70b62eb6)
		>&2 echo 'Operating on VEXXHOST'
		;;
	25b7cd46-495e-4862-a4a8-2222af553092)
		>&2 echo 'Operating on Kuryr Cloud'
		;;
	ca35156c-bb2b-4e38-9ef1-fa3651ce2bc5)
		>&2 echo 'Operating on vh-mecha-central'
		;;
	f6fe9835-9a6f-4377-aafb-48aa9dd9177b)
		>&2 echo 'Operating on vh-mecha-az0'
		;;
	*)
		>&2 echo "Refusing to run on anything else than the CI tenant"
		exit 1
esac

declare resultfile='/dev/null'

while getopts o: opt; do
	case "$opt" in
		o) resultfile="$OPTARG" ;;
		*) >&2 echo "Unknown flag: $opt"; exit 2 ;;
	esac
done

cat > "$resultfile" <<< '{}'

report() {
	declare \
		result='' \
		resource_type="$*"

	while read -r resource_id; do
		result=$(jq ".\"$resource_type\" += [\"$resource_id\"]" "$resultfile")
		cat > "$resultfile" <<< "$result"
		echo "$resource_id"
	done
}

leftover_clusters=$(./list-clusters.sh -ls)

for cluster_id in $leftover_clusters; do
	time ./destroy_cluster.sh -i "$(echo "$cluster_id" | report cluster)"
done

# Try again, this time via openstack commands directly
for cluster_id in $leftover_clusters; do
	time ./destroy_cluster.sh --force -i "$(echo "$cluster_id" | report cluster)"
done

# Clean leftover containers
openstack container list -f value -c Name \
	| grep -vf <(./list-clusters.sh -a) \
	| report container \
	| xargs --verbose --no-run-if-empty openstack container delete -r

for resource in 'volume snapshot' 'volume' 'floating ip' 'security group' 'keypair'; do
	if [[ ${resource} == 'volume' ]]; then
	  for r in $(./stale.sh -q "$resource"); do
	    status=$(openstack "${resource}" show -c status -f value "${r}")
		case "$status" in
			# For Cinder volumes, deletable states are documented here:
			# https://docs.openstack.org/api-ref/block-storage/v3/index.html?expanded=delete-a-volume-detail#delete-a-volume
			available|in-use|error|error_restoring|error_extending|error_managing)
				break
				;;
			*)
				echo "${resource} ${r} in wrong state: ${status}, will try to set it to 'error'"
				openstack "$resource" set --state error "$r" || >&2 echo "Failed to set ${resource} ${r} state to error, ${r} will probably fail to be removed..."
				;;
		esac
	  done
	fi
	# shellcheck disable=SC2086
	./stale.sh -q $resource | report $resource | xargs --verbose --no-run-if-empty openstack $resource delete
done
