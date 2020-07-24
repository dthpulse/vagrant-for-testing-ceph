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

ceph orch ps --daemon_type mon --refresh --format json | jq -r .[].hostname | grep "${osd_nodes[0]%%.*}"
