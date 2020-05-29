set -ex

echo "
#######################################
######  ses_monitor_failover.sh  ######
#######################################
"

. /tmp/config.conf


echo "### Calculating max number of monitors that can be putted down ###"
if [ $((${#monitor_minions[@]}%2)) -eq 0 ];then
    monitors_max_down=$((${#monitor_minions[@]}/2-1))
else
    monitors_max_down=$((${#monitor_minions[@]}/2))
fi

echo "### Stopping monitor services ###"
for mon2fail in $(seq 1 $monitors_max_down)
do
    mon2fail_fqdn=${monitor_minions[$mon2fail]}
    mon2fail=$(echo $mon2fail_fqdn | cut -d . -f 1)
    salt "$mon2fail_fqdn" service.stop ceph-mon@${mon2fail}.service
    salt "$mon2fail_fqdn" service.status ceph-mon@${mon2fail}.service
    sleep 120
    ceph -s
    stopped_minions+="$mon2fail_fqdn "
done
 
echo "### Starting previously stopped monitors ###"
for mon2start_fqdn in $stopped_minions
do
    mon2start=$(echo $mon2start_fqdn | cut -d . -f 1)
    salt "$mon2start_fqdn" service.start ceph-mon@${mon2start}.service
    salt "$mon2start_fqdn" service.status ceph-mon@${mon2start}.service
    sleep 45
    ceph -s
done

echo "### Making whole node(s) and all its services unaccessible ###"
for node2down in $(seq 1 $monitors_max_down)
do
    for node2block in $(echo ${monitor_minions[@]} | sed "s/${monitor_minions[$node2down]}//")
    do
        salt "${monitor_minions[$node2down]}" cmd.run "iptables -I INPUT -s $(echo $node2block | cut -d . -f 1) -j DROP"
    done
    salt "${monitor_minions[$node2down]}" cmd.run "iptables -L INPUT"
    sleep 180
    ceph -s
    nodesdown+="${monitor_minions[$node2down]} "
done

echo "### Bringing node(s) up ###"
for node2up in $nodesdown
do
    for rule in $(seq 1 $(salt "$node2up" cmd.run "iptables -L INPUT --line-numbers"  | grep DROP | wc -l))
    do
        salt "$node2up" cmd.run "iptables -D INPUT 1"
    done
    salt "${monitor_minions[$node2down]}" cmd.run "iptables -L INPUT"
done

sleep 90

echo "### Checking cluster health status ###"
ceph -s

