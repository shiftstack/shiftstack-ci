#!/usr/bin/env bash
format="|%20s | %11s | %10s | %10s |\n"
separa="----------------------------\n"
function report_usage () {
 _max=$(echo $2 | grep max | grep ${1} | awk '{print $2}')
 _used=$(echo $2 | grep Used | grep ${1} | awk '{print $2}')
 _utilization=$(echo "scale=2; ${_used}.00/${_max}.00 * 100" | bc)
 printf "$format" $1  "${_utilization}%" ${_max} ${_used}

}

IFS=
data=$(openstack limits show --absolute -f value)
printf $format Resource Utilization Max Used
printf "%s\n" "---------------------------------------------------------------"
for resource in Core RAM Instances SecurityGroups FloatingIps Volumes
do
report_usage $resource $data
done

 _max=$(echo $data | grep max | grep maxTotalVolumeGigabytes | awk '{print $2}')
 _used=$(echo $data | grep Used | grep totalGigabytesUsed | awk '{print $2}')
 _utilization=$(echo "scale=2; ${_used}.00/${_max}.00 * 100" | bc)
 printf "$format" VolumeStorage\(GB\)  "${_utilization}%" ${_max} ${_used}