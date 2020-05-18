set -ex

echo "
#########################################
######  clients_rbd_persistent.sh  ######
#########################################
"

. /tmp/config.conf

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)
num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num

# testing part

### checking command exit value
function exit_value () {
    if [ $(echo $?) -ne 0 ]
    then
        echo
        echo "$(tput setaf 1)ERROR $(tput sgr 0) $@"
        echo
        exit 1
    else
        echo
        echo "$@ - $(tput setaf 2)PASSED$(tput sgr 0)"
        echo
    fi
}

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

### testing RBD section
function rbd_test () {

    echo "##### running rbd test on $1 #####"
   
    cat /etc/ceph/ceph.client.admin.keyring | ssh $1 "cat > /etc/ceph/ceph.client.admin.keyring"
    exit_value "copying ceph keys"
    cat /etc/ceph/ceph.conf | ssh $1 "cat > /etc/ceph/ceph.conf"
    exit_value "copying ceph configs"
    ceph osd pool create rbd_persistent $pg_num $pgp_num
    ceph osd pool application enable rbd_persistent rbd
    exit_value "create pool rbd_persistent"
   
    ceph_health=$(ceph health)
   
    until [ "$ceph_health" == "HEALTH_OK" ]
    do
        sleep 10
        ceph_health=$(ceph health)
    done 
   
    ssh $1 "systemctl enable rbdmap.service; systemctl start rbdmap.service; modprobe rbd"
    
    if [ "$(ssh $1 grep 'VERSION_ID' /etc/os-release)" == 'VERSION_ID="16.04"' ]
    then
        ceph osd crush tunables legacy
        ubuntu16=true
    fi
   
    ssh $1 "rbd create rbd_persistent/image --size 1G"
    exit_value "create rbd image"
    rbd_dev=$(ssh $1 "rbd map rbd_persistent/image")
    exit_value "map RBD image"
    ssh $1 "echo "rbd_persistent/image    id=admin,keyring=/etc/ceph/ceph.client.admin.keyring" >> /etc/ceph/rbdmap"
    exit_value "create rbdmap config"
    ssh $1 "parted -s $rbd_dev mklabel gpt unit % mkpart 1 xfs 0 100"
    exit_value "create new label and partition"
    ssh $1 "mkfs.xfs ${rbd_dev}p1; mount ${rbd_dev}p1 /mnt; dd if=/dev/zero of=/mnt/testfile.txt bs=1024K count=50"
    exit_value "create filesystem and populate file"
    file_size=$(ssh $1 "dd if=/dev/zero of=/mnt/testfile.txt bs=1024K count=50" 2>&1 | awk 'END{print $1}')
    file_size_check=$(ssh $1 "du -sb /mnt/testfile.txt" | awk '{print $1}')
   
    if [ $file_size -ne $file_size_check ]
    then
        echo "$(tput setaf 1)ERROR$(tput sgr 0) - file size /mnt/testfile.txt doesn't match"
    else
        echo "file size /mnt/testfile.txt match" 
    fi
   
    ssh $1 "umount /mnt"
    ssh $1 "reboot"
    wait_for_server $1
   
    echo "Waiting until rbdmap service become active"
    until [ "$(ssh $1 systemctl is-active rbdmap.service)" == "active" ]
    do
        sleep 10
    done
    
    ssh $1 "lsblk $rbd_dev"
    exit_value "RBD mapped after reboot"
   
    ssh $1 "rbd unmap $rbd_dev"
    exit_value "unmount RBD"
    ceph osd pool rm rbd_persistent rbd_persistent --yes-i-really-really-mean-it
    exit_value "remove rbd_persistent pool"
    
    if $ubuntu16
    then
        ceph osd crush tunables default
    fi
    
    ubuntu16=false
     
}

### check if clients.conf file exists otherwise exit
test ! -f /tmp/clients.conf && exit

### proceed each client from clients.conf file
for client in $(cat /tmp/clients.conf | grep -v "^#" | sed 's/#.*//g;/^$/d')
do
    
    ### find what distribution is running on host
    if [[ ! -z $(ssh $client "grep "^ID=" /etc/os-release" | grep -i centos) ]]
    then
        distro=centos
    elif [[ ! -z $(ssh $client "grep "^ID=" /etc/os-release" | grep -i ubuntu) ]]
    then
        distro=ubuntu
    elif [[ ! -z $(ssh $client "grep "^ID=" /etc/os-release" | egrep -i 'suse|sles') ]]
    then
        distro=suse
    elif [[ ! -z $(ssh $client "grep "^ID=" /etc/os-release" | egrep -i 'rhel') ]]
    then
        distro=rhel
    elif [[ ! -z $(ssh $client "grep "^ID=" /etc/os-release" | egrep -i 'fedora') ]]
    then
        distro=fedora
    else
        echo "Not supported distribution found on client."
        exit
    fi
    
    if [ $distro == "centos" ]
    then
        ssh $client "yum -q -y install epel-release yum-plugin-priorities https://download.ceph.com/rpm-luminous/el7/noarch/ceph-release-1-1.el7.noarch.rpm" >/dev/null 2>&1
        exit_value "installing epel-release"
        ssh $client "sed -i -e "s/enabled=1/enabled=1\\\\npriority=1/g" /etc/yum.repos.d/ceph.repo"
        exit_value "enabling epel repo"
        ssh $client "yum -q -y update" >/dev/null 2>&1
        ssh $client "reboot"
        wait_for_server $client
        ssh $client "yum -q -y install ceph-common" > /dev/null 2>&1
        exit_value "install ceph packages"
        ssh $client "systemctl disable firewalld; systemctl stop firewalld" >/dev/null 2>&1
        exit_value "disable FW"
        rbd_test $client
    elif [ $distro == "ubuntu" ]
    then
        ssh $client "until [ -z \"$(ps -ef | grep apt | grep -v grep)\" ]; do sleep 5;done"
        ssh $client "apt-get update  && apt-get dist-upgrade -q -y > /dev/null 2>&1"
        ssh $client "apt-get install -y ceph-common"
        rbd_test $client
    elif [ $distro == "suse" ]
    then
     #ssh $client "SUSEConnect --cleanup; SUSEConnect -r 32d819432ec25499"
     #ssh $client "zypper -q dup -y; zypper -q in -y ceph-common"   
        ssh $client "zypper -q in -y ceph-common"
        rbd_test $client
    elif [ $distro == "rhel" ]
    then
        #update yum repos
        ssh $client "yum  --noplugins list >/dev/null 2>&1"
        exit_value "got packages list"
        ssh $client "yum  --noplugins update >/dev/null 2>&1"
        exit_value "checked for updates"
        
        #installing Ceph http://docs.ceph.com/docs/master/install/get-packages/#id3
        ssh $client "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm >/dev/null 2>&1"
        exit_value "installed EPEL release"
        
        ssh $client "su -c 'rpm -Uvh https://download.ceph.com/rpm-luminous/el7/noarch/ceph-release-1-1.el7.noarch.rpm' >/dev/null 2>&1"
        exit_value "installed ceph-release-1-1.el7.noarch.rpm"
        
        ssh $client "yum install -y ceph-common --skip-broken >/dev/null 2>&1"
        exit_value "installes ceph-common package"
     
        #disable firewall
        ssh $client "systemctl stop firewalld.service >/dev/null 2>&1"
        ssh $client "systemctl disable firewalld.service >/dev/null 2>&1"
        exit_value "disabled and stopped the firewalld service"
       
        rbd_test $client
    elif [ $distro == "fedora" ]
    then
        ssh $client "yum install -y ceph-common >/dev/null 2>&1"
        exit_value "installes ceph-common package"
       
        #disable firewall
        ssh $client "systemctl stop firewalld.service >/dev/null 2>&1"
        ssh $client "systemctl disable firewalld.service >/dev/null 2>&1"
        exit_value "disabled and stopped the firewalld service"
    
        rbd_test $client
    fi
done
