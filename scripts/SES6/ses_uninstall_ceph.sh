set -ex

echo "
#####################################
######  ses_uninstall_ceph.sh  ######
#####################################
"

. /tmp/config.conf

echo "### Purge Ceph ###"
salt-run state.orch ceph.purge 2>/dev/null
sleep 3
salt-run disengage.safety 2>/dev/null
sleep 3
salt-run state.orch ceph.purge 2>/dev/null

