set -x

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

### Getting random minion and its random OSD ###
osd_nodes=($osd_nodes)
random_minion_fqdn=${osd_nodes[0]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
random_osd=$(ceph osd tree | grep -A 1 $random_minion | grep -o "osd\.".* | awk '{print$1}')
random_osd="osd.0"
ceph_fsid="$(ceph fsid)"

### Bringing OSD out ###
ceph osd out $random_osd

### Displaying OSD tree ###
ceph osd tree

### Bringing OSD in ###
ceph osd in $random_osd

### Stopping service for random OSD on random minion ###
#salt "$random_minion_fqdn" service.stop ceph-osd@$(echo $random_osd | cut -d . -f 2) 2>/dev/null
ssh $random_minion_fqdn "systemctl stop ceph-${ceph_fsid}@${random_osd}.service"

### Removing OSD from crush map ###
ceph osd crush remove $random_osd

### Removing access data for OSD ###
ceph auth del $random_osd

### Bringing OSD down ###
ceph osd down $random_osd

### Removing OSD ###
ceph osd rm $random_osd

### Displaying OSD tree ###
ceph osd tree

sleep 3

### Cleaning the disk ###
osd_systemdisk=$(ssh $random_minion_fqdn "find /var/lib/ceph/${ceph_fsid}/$random_osd -type l -exec readlink \{\} \; | cut -d / -f 3 | while read line; do pvdisplay | grep -B 1 \$line | head -1 | awk '{print \$3}'; done")

if ! ssh $random_minion_fqdn "which sgdisk" >/dev/null 2>&1;then ssh $random_minion_fqdn "zypper in -y gptfdisk";fi

ssh $random_minion_fqdn "sgdisk -Z $osd_systemdisk" 2>/dev/null

ssh $random_minion_fqdn "sgdisk -o -g $osd_systemdisk" 2>/dev/null

ssh $random_minion_fqdn reboot || true

wait_for_server $random_minion_fqdn

ssh $random_minion_fqdn "lsblk -f" 2>/dev/null

### Ceph health status ###
ceph -s

