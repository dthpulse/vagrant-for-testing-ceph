set -ex

monitors_all=($monitors)
monitors=(${monitors_all[@]/$(hostname -f)})

monitor_mds=${monitors[0]}
monitor_mds_ip=$(ssh $monitor_mds "hostname -i")
ceph_fsid=$(ceph fsid)


function test_mds {
    local action=$1
    local filesystem_name=$2
    local label=$3
    local service_name="ceph-${ceph_fsid}@mds.${filesystem_name}*"
    ceph orch $action mds $filesystem_name 1 ${monitor_mds%.*}:$monitor_mds_ip $label
    sleep 30
    ssh $monitor_mds "systemctl is-active $service_name"
    ssh $monitor_mds "systemctl restart $service_name"
    sleep 10
    ssh $monitor_mds "systemctl is-active $service_name" 
    ssh $monitor_mds "systemctl stop $service_name"
    sleep 5
    ssh $monitor_mds "systemctl start $service_name"
    sleep 10
    ssh $monitor_mds "systmctl is-active $service_name"
    ceph fs ls 
    ceph config dump
    if [ "$action" == "update" ]
    then
        ceph orch mds rm $realm_name $zone_name
	    ceph config dump
	    ssh $monitor_mds "systemctl status $service_name"
    fi
}

# creates mds
ceph fs volume create testfs ${monitors[0]%%.*}
#test_mds apply testfs
output=$(ceph fs ls --format json | jq '.[0].name, .[0].data_pools[0], .[0].metadata_pool')
output_num=$(echo "$output" | wc -l)
if [ $output_num -ne 3 ]
then
   exit 1
fi


# change 
#test_mds update testfs label1
