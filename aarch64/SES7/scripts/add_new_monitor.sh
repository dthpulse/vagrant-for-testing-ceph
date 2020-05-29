set -ex

osd_nodes=($osd_nodes)
monitors=($monitors)
master=$master

ceph orch mon apply ${osd_nodes[0]%%.*}

timeout -k 180 180 ceph -s || exit 1
