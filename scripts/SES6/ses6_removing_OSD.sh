set -ex

echo "
###################################
######  ses_removing_OSD.sh  ######
###################################
"

. /tmp/config.conf

echo "### Getting random minion and its random OSD ###"
random_minion_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
random_osd=$(ceph osd tree | grep -A 1 $random_minion | grep -o "osd\.".* | awk '{print$1}')

echo "### Bringing OSD out ###"
ceph osd out $random_osd

echo "### Displaying OSD tree ###"
ceph osd tree

echo "### Bringing OSD in ###"
ceph osd in $random_osd

echo "### Stopping service for random OSD on random minion ###"
salt "$random_minion_fqdn" service.stop ceph-osd@$(echo $random_osd | cut -d . -f 2) 2>/dev/null

echo "### Removing OSD from crush map ###"
ceph osd crush remove $random_osd

echo "### Removing access data for OSD ###"
ceph auth del $random_osd

echo "### Bringing OSD down ###"
ceph osd down $random_osd

echo "### Removing OSD ###"
ceph osd rm $random_osd

echo "### Displaying OSD tree ###"
ceph osd tree

sleep 3

echo "### Cleaning the disk ###"
#osd_systemdisk=$(salt "$random_minion_fqdn" cmd.run "lsblk -o KNAME,MOUNTPOINT " | grep -w ceph-$(echo $random_osd | cut -d . -f 2))
#osd_sgdisk=$(echo $osd_systemdisk | awk '{print $1}' | tr -d [:digit:])
#osd_mountpoint=$(echo $osd_systemdisk | awk '{print $2}')
#
#salt "$random_minion_fqdn" cmd.run "umount -l $osd_mountpoint" 2>/dev/null
#salt "$random_minion_fqdn" cmd.run "sgdisk -Z /dev/$osd_sgdisk" 2>/dev/null
#salt "$random_minion_fqdn" cmd.run "sgdisk -o -g /dev/$osd_sgdisk" 2>/dev/null
#salt "$random_minion_fqdn" cmd.run "lsblk -f" 2>/dev/null

osd_id=$(echo $random_osd | cut -d . -f 2)

vg_name=$(salt "$random_minion_fqdn" cmd.run \
    "find /var/lib/ceph/osd/ceph-$osd_id -type l -name block -exec readlink {} \; | rev | cut -d / -f 2 | rev" \ 
	| tail -1 | tr -d ' ')

minion_osd_disk_partition=$(salt "$random_minion_fqdn" cmd.run \ 
    "pvdisplay -m 2>/dev/null | grep -B 1 $vg_name | grep \"PV Name\" | awk '{print \$3}' | cut -d / -f 3" \
	| tail -1 | tr -d ' ')

minion_osd_disk=$(echo $minion_osd_disk_partition | tr -d [:digit:])

salt $random_minion_fqdn cmd.run "dd if=/dev/zero of=/dev/$minion_osd_disk_partition bs=4096 count=1 oflag=direct"
salt $random_minion_fqdn cmd.run "sgdisk -Z --clear -g /dev/$minion_osd_disk"
size=$(salt $random_minion_fqdn cmd.run "blockdev --getsz /dev/$minion_osd_disk" | tail -1)
position=$((size/4096 - 33))
salt $random_minion_fqdn cmd.run "dd if=/dev/zero of=/dev/$minion_osd_disk bs=4096 count=33 seek=$position oflag=direct"

echo "rebooting $random_minion_fqdn"
salt $random_minion_fqdn system.reboot || true

echo "waiting for $random_minion_fqdn"
sleep 10
ping -q -c 3 $random_minion_fqdn >/dev/null 2>&1
until [ "$(echo $?)" -eq "0" ]
do
 sleep 10
 ping -q -c 3 $random_minion_fqdn >/dev/null 2>&1
done

ssh $random_minion_fqdn "exit" >/dev/null 2>&1
until [ $(echo $?) -eq 0 ]
do
 sleep 5
 ssh $random_minion_fqdn "exit" >/dev/null 2>&1
done

echo "Waiting until salt-minion service become active"
until [ "$(ssh $random_minion_fqdn systemctl is-active salt-minion)" == "active" ]
do
    sleep 10
done


echo "### Ceph health status ###"
ceph -s

