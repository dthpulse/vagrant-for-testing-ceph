set -x

monitor_minions_all=($monitors)
monitor_minions=(${monitor_minions_all[@]/$(hostname -f)})
ceph_fsid=$(ceph fsid)
echo "### Calculating max number of monitors that can be putted down ###"
if [ $((${#monitor_minions[@]}%2)) -eq 0 ];then
    monitors_max_down=$((${#monitor_minions[@]}/2))
else
    monitors_max_down=$((${#monitor_minions[@]}/2-1))
fi

echo "### Stopping monitor services ###"
for mon2fail in $(seq 1 $monitors_max_down)
do
    mon2fail_fqdn=${monitor_minions[$mon2fail]}
    mon2fail=$(echo $mon2fail_fqdn | cut -d . -f 1)
    ssh $mon2fail_fqdn "systemctl stop ceph-${ceph_fsid}@mon.${mon2fail}.service"
    ssh $mon2fail_fqdn "systemctl status ceph-${ceph_fsid}@mon.${mon2fail}.service"
    sleep 120
    ceph -s
    stopped_minions+="$mon2fail_fqdn "
done
 
echo "### Starting previously stopped monitors ###"
for mon2start_fqdn in $stopped_minions
do
    mon2start=$(echo $mon2start_fqdn | cut -d . -f 1)
    ssh $mon2start_fqdn "systemctl start ceph-${ceph_fsid}@mon.${mon2start}.service"
    ssh $mon2start_fqdn "systemctl status ceph-${ceph_fsid}@mon.${mon2start}.service"
    sleep 45
    ceph -s
done
