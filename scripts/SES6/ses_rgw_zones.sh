set -ex

##################################
########## RGW 2 zones ###########
##################################

echo "### Getting random minion to install RGW on ###"
random_minion_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)

echo "### Getting second random minion to install RGW on ###"
random_minion2_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
until [ "$random_minion2_fqdn" != "$random_minion_fqdn" ]
do
    random_minion2_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
done

random_minion2=$(echo $random_minion2_fqdn | cut -d . -f 1)


cat << EOF >> /srv/pillar/ceph/stack/global.yml

rgw_configurations:
  - us-east-1
  - us-east-2

EOF

for zone in us-east-1 us-east-2
do
cat << EOF >> /srv/salt/ceph/configuration/files/ceph.conf.d/${zone}.conf
[client.{{ client }}]
rgw frontends = \"civetweb port=80\"
rgw dns name = {{ fqdn }}
rgw enable usage log = true
rgw zone=${zone}
EOF
    cp /srv/salt/ceph/rgw/files/rgw.j2 /srv/salt/ceph/rgw/files/${zone}.j2
done

echo "### Configuring 2 RGW zones ###"

SYSTEM_ACCESS_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
SYSTEM_SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 40 | head -n 1)

radosgw-admin realm create --rgw-realm=gold --default
radosgw-admin zonegroup delete --rgw-zonegroup=default | true
radosgw-admin zonegroup create --rgw-zonegroup=us --endpoints=http://rgw1:80 --master --default
radosgw-admin zone create --rgw-zonegroup=us --rgw-zone=us-east-1 --endpoints=http://${random_minion_fqdn}:80 --access-key=$SYSTEM_ACCESS_KEY --secret=$SYSTEM_SECRET_KEY --default --master
radosgw-admin user create --uid=admin --display-name="Zone User" --access-key=$SYSTEM_ACCESS_KEY --secret=$SYSTEM_SECRET_KEY --system
radosgw-admin period get
radosgw-admin period update --commit
radosgw-admin zone create --rgw-zonegroup=us --rgw-zone=us-east-2 --access-key=$SYSTEM_ACCESS_KEY --secret=$SYSTEM_SECRET_KEY --endpoints=http://${random_minion2_fqdn}:80
radosgw-admin period update --commit
salt-run state.orch ceph.stage.1
sed -i 's/^role-rgw/#role-rgw/g' /srv/pillar/ceph/proposals/policy.cfg

cat << EOF >> /srv/pillar/ceph/proposals/policy.cfg
role-us-east-1/cluster/${random_minion_fqdn}.sls
role-us-east-2/cluster/${random_minion2_fqdn}.sls
EOF

salt-run state.orch ceph.stage.2 
salt-run state.orch ceph.stage.3
salt-run state.orch ceph.stage.4

salt $random_minion_fqdn cmd.run "systemctl status ceph-radosgw@us-east-1.\`hostname\`.service"
salt $random_minion2_fqdn cmd.run "systemctl status ceph-radosgw@us-east-2.\`hostname\`.service"

ceph health | grep "HEALTH_OK"

#echo "### Removing RGW ###"
#sed -i "s/^role-us-east/#role-us-east/g" /srv/pillar/ceph/proposals/policy.cfg
#salt-run state.orch ceph.stage.2 2>/dev/null
#salt-run state.orch ceph.stage.5 2>/dev/null
#ceph osd pool ls | grep rgw | xargs -I {} ceph osd pool rm {} {} --yes-i-really-really-mean-it
