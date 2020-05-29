set -ex

echo "
###################################################
######  clients_CephFS_test-mount_CephFS.sh  ######
###################################################
"

. /tmp/config.conf


echo "### getting minion for MDS ###"
random_minion_fqdn=${monitor_minions[$((`shuf -i 0-${#monitor_minions[@]} -n 1`-1))]}
sed -i '/^role-mds/d' /srv/pillar/ceph/proposals/policy.cfg
echo "role-mds/cluster/${random_minion_fqdn}.sls" >> /srv/pillar/ceph/proposals/policy.cfg

echo "### running salt ceph stages ###"
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

sleep 5

echo "### getting admin secret and mounting CephFS to /mnt/cephfs ###"
secret=$(grep key /etc/ceph/ceph.client.admin.keyring | sed 's/key\ =\ //')
monitors_count=$((${#monitor_minions[@]}))
mon_mounted=0

until [ $mon_mounted -eq $monitors_count ]
do
    mon_mount+="${monitor_minions[$mon_mounted]},"
    let mon_mounted+=1 
done
unset mon_mounted


for client in $(cat /tmp/clients.conf | grep -v "^#" | sed 's/#.*//g;/^$/d')
do
    ssh $client -tt << EOF

if [ -x "\$(command -v zypper)" ]
then 
    zypper in -y ceph-common
fi

if [ -x "\$(command -v yum)" ]
then 
    yum install -y ceph-common
fi

if [ -x "i\$(command -v apt-get)" ]
then 
    apt-get install -y ceph-common
fi

mkdir /mnt/cephfs

if ! mount -t ceph $(echo $mon_mount | sed 's/.$//'):/ /mnt/cephfs -o name=admin,secret=$(echo $secret | tr -d ' ')
then
   echo "ERROR - not mounted"
fi

echo "### displaying mount point ###"
if ! mount | grep "/mnt/cephfs"
then
    echo "ERROR - mount point not found"
fi

echo "### creating /mnt/cephfs/testfile.bin file on mountpoint ###"
dd if=/dev/zero of=/mnt/cephfs/testfile.bin oflag=direct bs=2M count=1000 status=progress

test ! -f /mnt/cephfs/testfile.bin && echo "ERROR - file /mnt/cephfs/testfile.bin doesn't exists" 

echo "### removing /mnt/cephfs/testfile.bin ###"
rm -f /mnt/cephfs/testfile.bin

test -f /mnt/cephfs/testfile.bin && echo "ERROR - file /mnt/cephfs/testfile.bin not removed"

echo "### unmounting CephFS ###"
umount /mnt/cephfs
rm -rf /mnt/cephfs
exit
EOF
done
