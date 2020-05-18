set -ex

monitors=($monitors)
monitors_update=(${monitors[@]/$(hostname -f)})
monitor_number=${#monitors_update[@]}
for i in ${!monitors_update[@]}
do
    monitor=${monitors_update[i]%%.*}
    monitor_ip=$(ssh $monitor "hostname -i")
    monitor_node+="${monitor}:$monitor_ip "
    rsync -avP /etc/ceph/ ${monitor}:/etc/ceph
done

ceph orchestrator mon update $monitor_number $monitor_node
ceph orchestrator mgr update $monitor_number $monitor_node
