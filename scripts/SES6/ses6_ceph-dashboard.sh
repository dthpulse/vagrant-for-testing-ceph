set -ex

echo "
######################################
######  ses6_ceph-dashboard.sh  ######
######################################
"

# enable dashboard module
ceph mgr module enable dashboard

# disable SSL
ceph config set mgr mgr/dashboard/ssl false

# reload dashboard
ceph mgr module disable dashboard
ceph mgr module enable dashboard

# create user
ceph dashboard ac-user-create testuser testuser administrator

sleep 15

# test if Dashboard UI is available
dashboard_url=$(ceph mgr services | grep dashboard | cut -d \" -f 4)

curl -k $dashboard_url >/dev/null 2>&1

if [ $(echo $?) -ne 0 ]
then
	exit 1
fi

