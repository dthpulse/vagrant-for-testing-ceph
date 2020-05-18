set -ex

monitors_all=($monitors)
monitors=(${monitors_all[@]/$(hostname -f)})

monitor_rgw=${monitors[0]}
monitor_rgw_ip=$(ssh $monitor_rgw "hostname -i")
ceph_fsid=$(ceph fsid)


function test_rgw {
    local action=$1
    local realm_name=$2
    local zone_name=$3
    local service_name="ceph-${ceph_fsid}@rgw.${realm_name}.${zone_name}*"
    ceph orchestrator rgw $action $realm_name $zone_name 1 ${monitor_rgw%.*}:$monitor_rgw_ip
    sleep 30
    ssh $monitor_rgw "systemctl is-active $service_name"
    ssh $monitor_rgw "systemctl restart $service_name"
    sleep 10
    ssh $monitor_rgw "systemctl is-active $service_name" 
    ssh $monitor_rgw "systemctl stop $service_name"
    sleep 5
    ssh $monitor_rgw "systemctl start $service_name"
    sleep 10
    ssh $monitor_rgw "systmctl is-active $service_name"
    radosgw-admin zone list --format json | jq -r .zones[] | grep $zone_name
    radosgw-admin realm list --format json | jq -r .realms[] | grep $realm_name
    ceph config dump
    if [ "$action" == "update" ]
    then
        ceph orchestrator rgw rm $realm_name $zone_name
	ceph config dump
	ssh $monitor_rgw "systemctl status $service_name"
    fi
}

# creates rgw
test_rgw add default default

# change realm
test_rgw update default realm1

# change zone
test_rgw update zone1 realm1
