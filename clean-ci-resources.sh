#!/usr/bin/env bash

CONFIG=${CONFIG:-cluster_config.sh}
if [ -r "$CONFIG" ]; then
	# shellcheck disable=SC1090
	source "./${CONFIG}"
fi

for arg in "$@"; do
  shift
  case "$arg" in
    "--delete-everything-older-than-5-hours") set -- "$@" "-f" ;;
    *) set -- "$@" "$arg"
  esac
done

declare resultfile='/dev/null'
declare DELETE=0
declare CLEANUP_FAILURES=0

# shellcheck disable=SC2220
while getopts :o:f opt; do
	case "$opt" in
		o) resultfile="$OPTARG" ;;
		f) DELETE=1 ;;
	esac
done

if [ $DELETE != 1 ]; then
	echo "Refusing to run unless passing the --delete-everything-older-than-5-hours option"
	exit 5
fi

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

set +e
for cluster_id in $leftover_clusters; do
	time ./destroy_cluster.sh -i "$(echo "$cluster_id" | report cluster)"
	# shellcheck disable=SC2181
	if [ $? != 0 ]; then
		CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
	fi
done

# Try again, this time via openstack commands directly
for cluster_id in $leftover_clusters; do
	time ./destroy_cluster.sh --force -i "$(echo "$cluster_id" | report cluster)"
	# shellcheck disable=SC2181
	if [ $? != 0 ]; then
		CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
	fi
done

# Clean leftover containers
openstack container list -f value -c Name \
	| grep -vf <(./list-clusters.sh -a) \
	| grep -v 'shiftstack-metrics' \
	| report container \
	| xargs --verbose --no-run-if-empty openstack container delete -r
# shellcheck disable=SC2181
if [ $? != 0 ]; then
	CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
fi

# Remaining resources. Order matters.
for resource in 'loadbalancer' 'server' 'router' 'subnet' 'network' 'volume snapshot' 'volume' 'floating ip' 'security group' 'keypair'; do
	case $resource in
		volume)
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
			# shellcheck disable=SC2086
			./stale.sh -q $resource | report $resource | xargs --verbose --no-run-if-empty openstack $resource delete
			;;
		loadbalancer)
		  for r in $(./stale.sh -q "$resource"); do
			status=$(openstack "${resource}" show -c provisioning_status -f value "${r}")
			case "$status" in
				ACTIVE|ERROR)
					# shellcheck disable=SC2086
					echo "$r" | report $resource | xargs --verbose openstack $resource delete --cascade
					;;
				*)
					;;
			esac
			done
			;;
		router)
		  for r in $(./stale.sh -q "$resource"); do
			subnets=$(openstack router show "$r" -c interfaces_info -f value | python -c "import sys; interfaces=eval(sys.stdin.read()); [print(i['subnet_id']) for i in interfaces]")
			for subnet in $subnets; do
			  openstack router remove subnet "$r" "$subnet"
			done
			# shellcheck disable=SC2086
			echo "$r" | report $resource | xargs --verbose openstack $resource delete
			done
			;;
		*)
			# shellcheck disable=SC2086
			./stale.sh -q $resource | report $resource | xargs --verbose --no-run-if-empty openstack $resource delete
			;;
	esac
	# shellcheck disable=SC2181
	if [ $? != 0 ]; then
		CLEANUP_FAILURES=$((CLEANUP_FAILURES + 1))
	fi
done
set -e
if [ $CLEANUP_FAILURES != 0 ]; then
	echo "$CLEANUP_FAILURES failure(s) was/were found during cleanup, check the logs for details"
	exit 1
fi
exit 0
