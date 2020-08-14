set -ex

master=$master
monitors=($monitors)
osd_nodes=($osd_nodes)

radosgw-admin realm create --rgw-realm=realm1 --default

radosgw-admin zonegroup create --rgw-zonegroup=zonegroup1 \
    --master --default

radosgw-admin zone create --rgw-zonegroup=zonegroup1 \
    --rgw-zone=zone1 --master --default


cat << EOF > /tmp/rgw.yaml
service_type: rgw
service_id: realm1.zone1
placement:
 hosts:
  - ${osd_nodes[0]%%.*}
  - ${osd_nodes[1]%%.*}
  - ${osd_nodes[2]%%.*}
EOF

ceph orch apply -i /tmp/rgw.yaml

n=1
until [ $n -ge 5 ]
do
    ceph orch ps --refresh --daemon_type rgw --format json \
    | jq -r .[].status_desc | grep error && break
    n=$((n+1))
    sleep 60
done

