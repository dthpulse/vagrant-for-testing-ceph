set -ex

monitors=($monitors)
osd_nodes=($osd_nodes)
master=$master

cat << EOF > /tmp/nfs.yaml
service_type: nfs
service_id: nfs
placement:
 hosts:
  - ${osd_nodes[0]%%.*}
  - ${osd_nodes[1]%%.*}
spec:
 pool: nfspool
 namespace: nfsnamespace
EOF

ceph osd pool create nfspool 256

ceph osd pool application enable nfspool nfs

ceph orch apply -i /tmp/nfs.yaml

while [ -z "$(ceph orch ps | awk '/nfs/ && /running/ {print $0}')" ]; do
    sleep 15
done

mount ${osd_node[0]%%.*}:/ /mnt

mount | grep mnt

touch /mnt/file.txt

