set -ex

osd_nodes=($osd_nodes)
monitors=($monitors)
master=$master

ceph orch apply mon ${osd_nodes[0]%%.*}

sleep 5

timeout -k 180 180 ceph -s || exit 1

ceph orch ps --daemon_type mon | grep osd-node1 || exit 1

