set -ex

function dashboard_url () {
    dashboard_url="$(ceph mgr services | jq -r .dashboard)"
}

ceph config set mgr mgr/dashboard/ssl false

ceph mgr module disable dashboard
ceph mgr module enable dashboard

sleep 15

dashboard_url

while [ "$dashboard_url" == "null" ] || [[ "$dashboard_url" == *"8443"* ]];do
    sleep 10
    dashboard_url
done

curl -k $dashboard_url >/dev/null 2>&1

if [ $(echo $?) -ne 0 ]
then
	        exit 1
fi
