set -ex

monitors=($monitors)
master=$master

random_minion_fqdn=${monitors[0]}

ceph fs volume create myfs ${random_minion_fqdn%%.*}

while [ "$(ceph fs ls --format json | jq -r .[].name)" != "myfs" ]
do
    sleep 5
done

secret=$(grep key /etc/ceph/ceph.client.admin.keyring | sed 's/key\ =\ //')
mount_monitors="$(echo "${monitors[@]}" | tr ' ' ',')"

for client in $(cat /tmp/clients.conf | grep -v "^#" | sed 's/#.*//g;/^$/d')
do
    ssh $client -tt << EOF

if [ -x "\$(command -v zypper)" ]
then 
    SUSEConnect -r deedc51104e549deb
    zypper in -y ceph-common
fi

if [ -x "\$(command -v yum)" ]
then 
    yum install -y ceph-common
fi

if [ -x "\$(command -v apt-get)" ]
then 
    apt-get install -y ceph-common
fi

mkdir /mnt/cephfs

mount -t ceph $mount_monitors:/ /mnt/cephfs -o name=admin,secret=$(echo $secret | tr -d ' ')

mount | grep "/mnt/cephfs" || exit 1

dd if=/dev/zero of=/mnt/cephfs/testfile.bin oflag=direct bs=2M count=1000 status=progress

rm -f /mnt/cephfs/testfile.bin

umount /mnt/cephfs
rm -rf /mnt/cephfs
exit
EOF
done
