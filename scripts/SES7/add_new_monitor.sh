set -ex

osd_nodes=($osd_nodes)
monitors=($monitors)
master=$master

ceph orch apply mon $(echo ${monitors[*]%%.*} ${osd_nodes[0]%%.*} | sed 's/\ /,/g')

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
