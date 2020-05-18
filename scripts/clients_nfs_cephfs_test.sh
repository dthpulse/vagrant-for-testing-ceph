set -ex

echo "
#########################################
######  clients_nfs_cephfs_test.sh ######
#########################################
"

. /tmp/config.conf

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

### check if clients.conf file exists otherwise exit
test ! -f /tmp/clients.conf && exit

### Getting random minion for Ganesha installation
random_minion=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}

### Checking if Ganesha is deployed
if [ ! "$(salt-run select.minions roles=ganesha)" ]
then
    ### Going to deploy Ganesha
    echo "role-ganesha/cluster/${random_minion}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
    deploy_ganesha=true
else
    ### Ganesha is deployed
    random_minion=$(salt-run select.minions roles=ganesha | awk '{print $2}')
fi

### Checking if MDS is deployed
if [ ! "$(salt-run select.minions roles=mds)" ]
then
    ### Going to deploy MDS
    echo "role-mds/cluster/${random_minion}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
    deploy_mds=true
fi

if [ $deploy_ganesha ] || [ $deploy_mds ]
then
    salt-run state.orch ceph.stage.2 2>/dev/null
    salt-run state.orch ceph.stage.3 2>/dev/null
    salt-run state.orch ceph.stage.4 2>/dev/null
fi

### Configuring Ganesha export with Squash = none
ssh $random_minion "sed -i '/Protocols.*/a Squash = none;' /etc/ganesha/ganesha.conf"
### Restarting nfs-ganesha
ssh $random_minion "systemctl restart nfs-ganesha"

deploy_ganesha=false
deploy_mds=false

### Proceed each client from clients.conf file
for client in $(cat /tmp/clients.conf | grep -v ^"#" | sed 's/#.*//g;/^$/d')
do
    if ssh $client "mount ${random_minion}:/cephfs/ /mnt"
    then
  	    exit_value "NFS mounted on $client"
        ssh $client "dd if=/dev/zero of=/mnt/${client}.bin bs=1M count=1024 status=progress oflag=direct"
    else
	    exit_value "NFS not mounted on $client"
    fi
 
    ssh $client "rm -f /mnt/${client}.bin"
    ssh $client "umount /mnt"
done
