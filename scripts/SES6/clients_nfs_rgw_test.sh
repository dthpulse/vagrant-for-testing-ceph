set -ex

echo "
##########################################
######  clients_nfs_rgw_test.sh  ######
##########################################
"

. /tmp/config.conf

echo "### checking command exit value"
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

echo "### check if clients.conf file exists otherwise exit"
test ! -f /tmp/clients.conf && exit

echo "### Getting random minion for Ganesha installation"
random_minion=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}

echo "### Checking if Ganesha is deployed"
if [ ! "$(salt-run select.minions roles=ganesha)" ]
then
    echo "### Going to deploy Ganesha"
    echo "role-ganesha/cluster/${random_minion}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
    deploy_ganesha=true
else
    echo "### Ganesha is deployed"
    random_minion=$(salt-run select.minions roles=ganesha | awk '{print $2}')
fi

echo "### Checking if RGW is deployed"
if [ ! "$(salt-run select.minions roles=rgw)" ] && [ ! "$(salt-run select.minions roles=us-east-\*)" ]
then
    echo "### Going to deploy RGW"
    echo "role-rgw/cluster/${random_minion}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
    deploy_rgw=true
fi

if [ $deploy_ganesha ] || [ $deploy_rgw ]
then
    salt-run state.orch ceph.stage.2 2>/dev/null
    salt-run state.orch ceph.stage.3 2>/dev/null
    salt-run state.orch ceph.stage.4 2>/dev/null
fi

echo "### Configuring Ganesha export with Squash = none"
ssh $random_minion "sed -i '/Protocols.*/a Squash = none;' /etc/ganesha/ganesha.conf"
echo "### Restarting nfs-ganesha"
ssh $random_minion "systemctl restart nfs-ganesha"

deploy_ganesha=false
deploy_rgw=false

echo "### Proceed each client from clients.conf file"
for client in $(cat /tmp/clients.conf | grep -v ^"#" | sed 's/#.*//g;/^$/d')
do
    if ssh $client "mount ${random_minion}:/admin /mnt"
    then
        exit_value "NFS mounted on $client"
        ssh $client "df -h /mnt"
        ssh $client "mkdir /mnt/$client"
        ssh $client "dd if=/dev/zero of=/mnt/${client}/${client}.bin bs=1M count=1024 status=progress oflag=direct"
    else
   	    exit_value "NFS not mounted on $client"
    fi
    
    ssh $client "rm -rf /mnt/${client}"
    ssh $client "umount /mnt"
done

echo "removing RGW"
sed -i "s/^role-rgw/#role-rgw/g" /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.5 2>/dev/null

ceph osd pool ls | grep rgw | xargs -I {} ceph osd pool rm {} {} --yes-i-really-really-mean-it
