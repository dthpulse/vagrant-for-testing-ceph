set -ex

master=$master
osd_nodes=($osd_nodes)
monitors=($monitors)

ceph osd pool create pool1 128 128

ceph osd pool application enable pool1 rbd

rbd create -p pool1 image1 --size=1G

sleep 10

ceph orch ps --daemon_type osd

osds_id=($(ceph orch ps --daemon_type osd --format=json | jq -r .[].daemon_id))

orig_num_osds=${#osds_id[@]}

if [ $orig_num_osds -gt 4 ]; then
    remove=2
else
    remove=1
fi

for i in $(seq 1 $remove); do
    ceph orch osd rm ${osds_id[i]}
done

ceph orch osd rm status

while [ $(ceph osd stat --format=json | jq -r .num_osds) -ne $(($orig_num_osds - $remove)) ]; do
    sleep 60
done
