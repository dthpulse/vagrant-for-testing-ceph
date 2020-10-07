set -ex

master=$master
monitors=($monitors)
osd_nodes=($osd_nodes)

cat << EOF > /root/mon.yaml
service_type: mon
placement:
 hosts:
EOF

for monitor in ${monitors[*]%%.*}; do
cat << EOF >> /root/mon.yaml
  - $monitor
EOF
done

sed -i "/${monitors[1]%%.*}/d" /root/mon.yaml

ceph orch apply -i /root/mon.yaml

sleep 60

status="$(ceph orch ps --daemon_type mon --format json | jq -r .[].daemon_id)"

timeout 10m bash -c "until [ -z $(echo "$status" | grep ${monitors[1]%%.*}) ] ;do sleep 10;done"

if [ "$(echo $status | grep ${monitors[1]%%.*})" ]; then
    exit 1
fi
