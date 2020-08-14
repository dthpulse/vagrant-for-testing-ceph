set -ex

monitors=($monitors)
master=$master

random_minion_fqdn=${monitors[0]}

ceph fs volume create myfs ${random_minion_fqdn%%.*}

while [ "$(ceph fs ls --format json | jq -r '.[].name')" != "myfs" ]
do
    sleep 5
done

secret=$(grep key /etc/ceph/ceph.client.admin.keyring | sed 's/key\ =\ //')
mount_monitors="$(echo "${monitors[@]}" | tr ' ' ',')"

mkdir /mnt/cephfs

while [ "$(ceph orch ps --daemon_type mds --format json | jq -r '.[].status_desc')" != "running" ];do
    sleep 10
done

sleep 15

mount -t ceph $mount_monitors:/ /mnt/cephfs -o name=admin,secret=$(echo $secret | tr -d ' ')

mount | grep "/mnt/cephfs"

dd if=/dev/zero of=/mnt/cephfs/testfile.bin oflag=direct bs=1M count=100 status=progress

rm -f /mnt/cephfs/testfile.bin

