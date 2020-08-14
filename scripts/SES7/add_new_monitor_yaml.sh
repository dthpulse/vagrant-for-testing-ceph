set -ex

master=$master
monitors=($monitors)
osd_nodes=($osd_nodes)

cat << EOF > new_mon.yaml
service_type: mon
placement:
 hosts:
EOF

for monitor in ${monitors[*]%%.*}; do
cat << EOF >> new_mon.yaml
  - $monitor
EOF
done

cat << EOF >> new_mon.yaml
  - ${osd_nodes[0]%%.*}
EOF

ceph orch apply -i new_mon.yaml

sleep 60

n=1
until [ $n -ge 5 ]
do
   status="$(ceph orch ps --daemon_type mon --format json | jq -r .[].daemon_id)"
   echo "$status" | grep "${osd_nodes[0]}" && break
   n=$((n+1))
   sleep 60
done

if [ "$status" != "${osd_nodes[0]}" ]; then
    exit 1
fi
