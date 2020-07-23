set -ex

osd_nodes=($osd_nodes)
monitors=($monitors)
master=$master

ceph orch apply mon $(echo ${monitors[*]%%.*} ${osd_nodes[0]%%.*} | sed 's/\ /,/g')

sleep 5

timeout -k 180 180 ceph -s || exit 1

ceph orch ps --daemon_type mon --refresh | grep osd-node1 || exit 1
