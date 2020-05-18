set -ex

echo "
##########################################
######  ses_install_nfs_ganesha.sh  ######
##########################################
"

. /tmp/config.conf

echo "### Getting random minion for Ganesha installation ###"
random_minion=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}

echo "### Adding Ganesha role to policy.cfg file ###"
echo "role-ganesha/cluster/${random_minion}.sls" >> /srv/pillar/ceph/proposals/policy.cfg

echo "### Getting 2nd random minion ###"
random_minion2=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
until [ "$random_minion2" != "$random_minion" ]
do 
    random_minion2=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
done 

echo "### Adding MDS role"
if [ -z "$(salt-run select.minions roles=mds)" ]
then
	echo "role-mds/cluster/${random_minion2}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
fi

echo "role-ganesha/cluster/${random_minion2}.sls" >> /srv/pillar/ceph/proposals/policy.cfg

echo "### Deploying Ganesha ###"
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

echo "### Getting cluster health status ###"
ceph -s

sleep 5

echo "### Restarting Ganesha service on both minions ###"
salt "$random_minion" service.status nfs-ganesha.service 2>/dev/null
salt "$random_minion2" service.status nfs-ganesha.service 2>/dev/null
salt "$random_minion" service.restart nfs-ganesha.service 2>/dev/null
salt "$random_minion2" service.restart nfs-ganesha.service 2>/dev/null

sleep 15

echo "### Checking if service is running ###"
salt "$random_minion" service.status nfs-ganesha.service | grep -i "true" 2>/dev/null

if [ $? -ne 0 ]
then
    logger -t "NFS-GANESHA on minion" ERROR service.status nfs-ganesha ${random_minion} not running
fi 

salt "$random_minion2" service.status nfs-ganesha.service | grep -i "true" 2>/dev/null

if [ $? -ne 0 ]
then
    logger -t "NFS-GANESHA on minion" ERROR service.status nfs-ganesha ${random_minion2} not running
fi 

echo "### Removing Ganesha service ###"
sed -i "s/^role-ganesha\/cluster\/$random_minion2/#role-ganesha\/cluster\/$random_minion2/g" /srv/pillar/ceph/proposals/policy.cfg

salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.5 2>/dev/null

sleep 10

echo "### Getting cluster health ###"
ceph -s

