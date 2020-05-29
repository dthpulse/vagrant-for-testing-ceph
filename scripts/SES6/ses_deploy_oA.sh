set -ex

echo "
################################
######  ses_deploy_oA.sh  ######
################################
"

. /tmp/config.conf

echo "### Adding oA role to policy.cfg file ###"
sed -i '/^role-openattic/d' /srv/pillar/ceph/proposals/policy.cfg
echo "role-openattic/cluster/${master}*.sls" >> /srv/pillar/ceph/proposals/policy.cfg

echo "### Deploying oA ###"
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

sleep 5

echo "### Applying salt-api ###"
salt-call state.apply ceph.salt-api 2>/dev/null

sleep 15

echo "### Playing with oA service - status, restart, status ###"
systemctl status openattic-systemd.service
systemctl restart openattic-systemd.service
sleep 5
systemctl status openattic-systemd.service

echo "### Removing oA ###"
sed -i 's/^role-openattic/#role-openattic/g' /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null 
salt-run state.orch ceph.stage.5 2>/dev/null

sleep 5

echo "### Redeploying oA ###"
sed -i 's/^#role-openattic/role-openattic/g' /srv/pillar/ceph/proposals/policy.cfg
salt-run state.orch ceph.stage.2 2>/dev/null
salt-run state.orch ceph.stage.3 2>/dev/null
salt-run state.orch ceph.stage.4 2>/dev/null

sleep 5

echo "### Getting oA service status"
systemctl status openattic-systemd.service

sleep 5

