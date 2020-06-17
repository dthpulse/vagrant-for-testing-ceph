set -ex

echo "
###################################
######  ses_removing_OSD.sh  ######
###################################
"

. /tmp/config.conf

### wait till server is available over SSH
function wait_for_server () {
    sleep 10
    ping -q -c 3 $1 >/dev/null 2>&1
    until [ "$(echo $?)" -eq "0" ]
    do
        sleep 10
        ping -q -c 3 $1 >/dev/null 2>&1
    done
   
    ssh $1 "exit" >/dev/null 2>&1
    until [ $(echo $?) -eq 0 ]
    do
        sleep 5
        ssh $1 "exit" >/dev/null 2>&1
    done
}

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
osd_systemdisk=$(ssh $random_minion_fqdn "find /var/lib/ceph/osd/ceph-$(echo $random_osd | cut -d . -f 2) -type l -exec readlink \{\} \; | cut -d / -f 3 | while read line; do pvdisplay | grep -B 1 \\\$line | head -1 | awk '{print \\\$3}'; done")

ssh $random_minion_fqdn "sgdisk -Z $osd_systemdisk" 2>/dev/null

ssh $random_minion_fqdn "sgdisk -o -g $osd_systemdisk" 2>/dev/null

ssh $random_minion_fqdn reboot | true

wait_for_server $random_minion_fqdn

ssh $random_minion_fqdn "lsblk -f" 2>/dev/null

echo "### Ceph health status ###"
ceph -s

