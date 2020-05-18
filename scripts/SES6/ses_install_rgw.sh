set -ex

echo "
##################################
######  ses_install_rgw.sh  ######
##################################
"

. /tmp/config.conf

rgw_sls="
rgw_configurations:
  rgw:
    users:
      - { uid: "admin", name: "admin", email: "demo@demo.nil", system: True }
"

echo "$rgw_sls" | sed '/^$/d' >> /srv/pillar/ceph/rgw.sls

echo "### Getting random minion to install RGW on ###"
random_minion_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1`

echo "role-rgw/cluster/${random_minion_fqdn}.sls" >> /srv/pillar/ceph/proposals/policy.cfg

echo "### Getting second random minion to install RGW on ###"
random_minion2_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
until [ "$random_minion2_fqdn" != "$random_minion_fqdn" ]
do 
    random_minion2_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
done 

random_minion2=$(echo $random_minion2_fqdn | cut -d . -f 1)

echo "role-rgw/cluster/${random_minion2_fqdn}.sls" >> /srv/pillar/ceph/proposals/policy.cfg

salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

ceph health | grep "HEALTH_OK"

salt "$random_minion_fqdn" service.status ceph-radosgw@rgw.${random_minion}.service 2>/dev/null
salt "$random_minion2_fqdn" service.status ceph-radosgw@rgw.${random_minion2}.service 2>/dev/null
salt "$random_minion_fqdn" service.restart ceph-radosgw@rgw.${random_minion}.service 2>/dev/null
salt "$random_minion2_fqdn" service.restart ceph-radosgw@rgw.${random_minion2}.service 2>/dev/null

sleep 15

salt "$random_minion_fqdn" service.status ceph-radosgw@rgw.${random_minion}.service | grep -i "true" 2>/dev/null
salt "$random_minion2_fqdn" service.status ceph-radosgw@rgw.${random_minion2}.service | grep -i "true" 2>/dev/null

sed -i "s/^role-rgw\/cluster\/$random_minion2_fqdn/#role-rgw\/cluster\/$random_minion2_fqdn/g" /srv/pillar/ceph/proposals/policy.cfg

salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.5 2>/dev/null

ceph health | grep "HEALTH_OK"

sed -i "s/^#role-rgw\/cluster\/$random_minion2_fqdn/role-rgw\/cluster\/$random_minion2_fqdn/g" /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

sed -i "s/^role-rgw/#role-rgw/g" /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.5 2>/dev/null

ceph osd pool ls | grep rgw | xargs -I {} ceph osd pool rm {} {} --yes-i-really-really-mean-it

ceph health | grep "HEALTH_OK"
