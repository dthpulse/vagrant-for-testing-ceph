set -x

pg_num=128
pgp_num=$pg_num

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

function exit_code () {
    if [ $(echo $?) -ne 0 ]
    then
        exit 1
    fi
}

function rbd_test () {

    cat /etc/ceph/ceph.client.admin.keyring | ssh $1 "cat > /etc/ceph/ceph.client.admin.keyring"
    cat /etc/ceph/ceph.conf | ssh $1 "cat > /etc/ceph/ceph.conf"
    ceph osd pool create rbd_persistent $pg_num $pgp_num
    ceph osd pool application enable rbd_persistent rbd

    ceph_health=$(ceph health)

    until [ "$ceph_health" == "HEALTH_OK" ]
    do
        sleep 10
        ceph_health=$(ceph health)
    done

    ssh $1 "systemctl enable rbdmap.service; systemctl start rbdmap.service; modprobe rbd"
    exit_code
    ssh $1 "rbd create rbd_persistent/image --size 1G"
    exit_code
    rbd_dev=$(ssh $1 "rbd map rbd_persistent/image")
    ssh $1 "echo "rbd_persistent/image    id=admin,keyring=/etc/ceph/ceph.client.admin.keyring" >> /etc/ceph/rbdmap"
    exit_code
    ssh $1 "parted -s $rbd_dev mklabel gpt unit % mkpart 1 xfs 0 100"
    exit_code
    ssh $1 "mkfs.xfs ${rbd_dev}p1; mount ${rbd_dev}p1 /mnt; dd if=/dev/zero of=/mnt/testfile.txt bs=1024K count=50"
    exit_code
    ssh $1 "umount /mnt"
    exit_code
    ssh $1 "reboot"

    wait_for_server $1

    until [ "$(ssh $1 systemctl is-active rbdmap.service)" == "active" ]
    do
        sleep 10
    done

    ssh $1 "lsblk $rbd_dev"
    ssh $1 "rbd unmap $rbd_dev"
    ceph osd pool rm rbd_persistent rbd_persistent --yes-i-really-really-mean-it
}

for client in $(cat /tmp/clients.conf)
do
    if [ "$client" == "sles11sp4" ]
    then
        ssh $client "suse_register -a regcode-sles=C72B0C12F8D420 -a email=dpolom@suse.com"
        ssh $client "zypper -qqq in -y ceph-common"
	rbd_test $client
    elif [ "$client" == "sles12sp4" ]
    then
	ssh $client "SUSEConnect -r deedc51104e549deb"
	ssh $client "zypper -qqq up -y"
        ssh $client "zypper -qqq in -y ceph-common"
	rbd_test $client
	ssh $client "SUSEConnect -d -c"
    elif [ "$client" == "sle15sp1" ]
    then
	ssh $client "SUSEConnect -r deedc51104e549deb"
	ssh $client "zypper -qqq up -y"
        ssh $client "zypper -qqq in -y ceph-common"
	rbd_test $client
	ssh $client "SUSEConnect -d -c"
    elif [ "$client" == "sles-es76" ]
    then 
        ssh $client -tt << EOF
        yum --nogpg install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        yum --nogpg install -y https://download.ceph.com/rpm-luminous/el7/noarch/ceph-release-1-1.el7.noarch.rpm    
        yum --nogpg install -y ceph-common
        systemctl stop firewalld.service
        systemctl disable firewalld.service
        exit
EOF
	rbd_test $client
    elif [ "$client" == "sles-es80" ]
    then
        ssh $client -tt << EOF
        yum --nogpg install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        yum --nogpg install -y https://download.ceph.com/rpm-octopus/el8/noarch/ceph-release-1-1.el8.noarch.rpm
        yum --nogpg install -y ceph-common
        systemctl stop firewalld.service
        systemctl disable firewalld.service
        exit
EOF
	rbd_test $client
    elif [ "$client" == "ubuntu164" ] || [ "$client" == "ubuntu184" ]
    then
        ceph osd crush tunables legacy
        ssh $client "apt-get install -y ceph-common"
	rbd_test $client
	ceph osd crush tunables default
    fi
done


