set -ex

osd_nodes=($osd_nodes)
monitors=($monitors)
master=$master

ceph orch apply mon ${osd_nodes[0]%%.*}

timeout -k 180 180 ceph -s || exit 1
