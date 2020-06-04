set -ex

ssh $master "ceph-salt config /cephadm_bootstrap/dashboard/username set admin"
ssh $master "ceph-salt config /cephadm_bootstrap/dashboard/password set admin"

ceph config set mgr mgr/dashboard/ssl false

ceph mgr module disable dashboard
ceph mgr module enable dashboard

dashboard_url="$(ceph mgr services | jq -r .dashboard)"

curl -k $dashboard_url >/dev/null 2>&1

if [ $(echo $?) -ne 0 ]
then
	        exit 1
fi
