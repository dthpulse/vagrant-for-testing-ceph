set -ex

echo "
#######################################
######  ses_ceph_health_cmds.sh  ######
#######################################
"

. /tmp/config.conf

### Getting Ceph health
echo "ceph health"
ceph health
echo "ceph -s"
ceph -s
