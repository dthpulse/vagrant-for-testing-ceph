set -ex

echo "
#######################################
######  ses_iSCSI_gw-LUN_map.sh  ######
#######################################
"

. /tmp/config.conf

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)
num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

function power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num

# testing part

lrbd () {
cat << EOF > /root/lrbd.conf
   {
        "auth": [ { "authentication": "none", "target": "$1" } ],
        "targets": [ { "hosts": [ { "host": "$2", "portal": "portal-${2}" } ], "target": "$1" } ],
        "portals": [ { "name": "portal-${2}", "addresses": [ "$3" ] } ],
        "pools": [ { "pool": "iscsi-images", "gateways": [ { "target": "$1", "tpg": [ { "image": "testvol" } ] } ] } ]
    }
EOF
}

echo "### Deploy IGW ###"
random_minion_fqdn=${monitor_minions[$((`shuf -i 0-${#monitor_minions[@]} -n 1`-1))]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
sed -i '/^role-igw/d' /srv/pillar/ceph/proposals/policy.cfg
echo "role-igw/cluster/${random_minion_fqdn}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
echo "role-igw/stack/default/ceph/minions/${random_minion_fqdn}.yml" >> /srv/pillar/ceph/proposals/policy.cfg

salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

sleep 5

echo "### Installation of pattern ceph_iscsi ###"
salt "$random_minion_fqdn" cmd.run "zypper in -l -t pattern -y ceph_iscsi" 2>/dev/null

echo "### getting random minion iqn ###"
random_minion_iqn=$(salt "$random_minion_fqdn" cmd.run "grep ^InitiatorName= /etc/iscsi/initiatorname.iscsi | cut -d = -f 2" 2>/dev/null | tail -1 | tr -d ' ')

echo "### getting random minion ip ###"
random_minion_ip=$(salt "$random_minion_fqdn" network.ip_addrs 2>/dev/null | tail -1 | tr -d - | tr -d ' ')

echo "### Creating image in pool ###"
test -z $(ceph osd pool ls | grep iscsi-images) && ceph osd pool create iscsi-images $pg_num $pgp_num replicated

while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

if ! rbd --pool iscsi-images create --size=10G testvol
then
    exit 1
fi

echo "### Modifying the lrbd configuration on target ###"
lrbd $random_minion_iqn $random_minion $random_minion_ip
salt-cp "$random_minion_fqdn" /root/lrbd.conf /root/lrbd.conf 2>/dev/null
salt-cp "$random_minion_fqdn" /etc/ceph/ceph.client.admin.keyring /etc/ceph 2>/dev/null
salt "$random_minion_fqdn" cmd.run "lrbd -o > /root/lrbd.conf.old" 2>/dev/null
salt "$random_minion_fqdn" cmd.run "lrbd -f /root/lrbd.conf" 2>/dev/null
sleep 5
salt "$random_minion_fqdn" cmd.run "systemctl restart lrbd" 2>/dev/null

echo "### iscsiadm on initiator ###"
iscsiadm -m discovery -t sendtargets -p $random_minion_fqdn
iqn=$(iscsiadm -m discovery -t sendtargets -p $random_minion_fqdn | grep -o iqn.*)
iscsiadm -m node -T $iqn -p $random_minion_fqdn -l
sleep 5

echo "### getting, formating and mountig iSCSI device ###"
iscsi_device=$(dmesg | grep -i "Attached SCSI disk" | grep -o .*Attached | awk '{print $(NF-1)}' | tr -d [:punct:] | tail -1)
parted /dev/$iscsi_device mklabel gpt unit % mkpart 1 xfs 0 100
sleep 5
mkfs.xfs -f /dev/${iscsi_device}1
if ! mount /dev/${iscsi_device}1 /mnt
then
    exit 1
fi

echo "### creating test file under mount point ###"
dd if=/dev/zero of=/mnt/iscsitest.bin oflag=direct status=progress bs=2M count=1000
test ! -f /mnt/iscsitest.bin && echo "file /mnt/iscsitest.bin doesn't exist"
if ! rm /mnt/iscsitest.bin
then
    echo "cannot remove file /mnt/iscsitest.bin"
fi

echo "### cleaning ###"
umount /mnt
iscsiadm -m node -T $iqn -p $random_minion_fqdn -u
iscsiadm -m node -o delete -T $iqn

salt "$random_minion_fqdn" cmd.run "systemctl stop lrbd" 2>/dev/null
rbd rm -p iscsi-images testvol

### part for testing iSCSI with authentication

echo "### creating new image in the pool ###"
if ! rbd --pool iscsi-images create --size=10G testvol
then
    exit 1
fi

echo "### Modifying the lrbd configuration on target ###"
sed -i 's/"authentication": "none"/"authentication": "tpg", "tpg": { "userid":"demo", "password":"demo" }/' /root/lrbd.conf
salt-cp "$random_minion_fqdn" /root/lrbd.conf /root/lrbd.conf 2>/dev/null
salt "$random_minion_fqdn" cmd.run "lrbd -f /root/lrbd.conf" 2>/dev/null
sleep 5
salt "$random_minion_fqdn" cmd.run "systemctl start lrbd" 2>/dev/null

echo "### setting initiator for authentication ###"
echo -e "node.session.auth.username = demo\nnode.session.auth.password = demo" >> /etc/iscsi/iscsid.conf
systemctl restart iscsi

echo "### iscsiadm section, discovery, attaching ###"
iscsiadm -m discovery -t sendtargets -p $random_minion_fqdn
iscsiadm -m node -T $iqn -p $random_minion_fqdn -l
sleep 5

echo "### getting, formating and mountig iSCSI device ###"
iscsi_device=$(dmesg | grep -i "Attached SCSI disk" | grep -o .*Attached | awk '{print $(NF-1)}' | tr -d [:punct:] | tail -1)
parted /dev/$iscsi_device mklabel gpt unit % mkpart 1 xfs 0 100
sleep 5
mkfs.xfs -f /dev/${iscsi_device}1
if ! mount /dev/${iscsi_device}1 /mnt
then
    exit 1
fi

echo "### creating file under mount point ###"
dd if=/dev/zero of=/mnt/iscsitest.bin oflag=direct status=progress bs=2M count=1000
test ! -f /mnt/iscsitest.bin && echo "file /mnt/iscsitest.bin doesn't exist"

echo "### final cleaning ###"
if ! rm /mnt/iscsitest.bin
then
    echo "cannot remove file /mnt/iscsitest.bin"
fi
umount /mnt
iscsiadm -m node -T $iqn -p $random_minion_fqdn -u
iscsiadm -m node -o delete -T $iqn
salt "$random_minion_fqdn" cmd.run "systemctl stop lrbd" 2>/dev/null
salt "$random_minion_fqdn" cmd.run "rm -f /etc/ceph/ceph.client.admin.keyring" 2>/dev/null
ceph osd pool rm iscsi-images iscsi-images --yes-i-really-really-mean-it
sed -i '/^role-igw/d' /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.5 2>/dev/null

