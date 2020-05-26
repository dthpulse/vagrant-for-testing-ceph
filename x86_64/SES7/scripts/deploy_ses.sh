set -ex

monitors=($monitors)
osd_nodes=($osd_nodes)

systemctl restart salt-master

sleep 240

salt \* saltutil.sync_all

sleep 15

ceph-salt config /ceph_cluster/minions add "*"
ceph-salt config /ceph_cluster/roles/admin add "$master"
ceph-salt config /ceph_cluster/roles/cephadm add "$master"

ceph-salt config /ceph_cluster/roles/bootstrap set "${monitors[0]}"

for i in ${monitors[@]}
do
    ceph-salt config /ceph_cluster/roles/admin add "$i"
    ceph-salt config /ceph_cluster/roles/cephadm add "$i"
done

ceph-salt config /ssh generate
ceph-salt config /time_server/server_hostname set "$master"
ceph-salt config /time_server/external_servers add "ntp.suse.cz"
ceph-salt config /containers/registries add prefix=registry.suse.de location=192.168.122.1:5000 insecure=true
ceph-salt config /containers/images/ceph set "registry.suse.de/suse/sle-15-sp2/update/products/ses7/milestones/containers/ses/7/ceph/ceph"
ceph-salt config ls

ceph-salt status

ceph-salt export > myconfig.json

ceph-salt apply --non-interactive

for node in ${osd_nodes[@]%%.*}
do
    ceph orch host add $node
done

ceph orch apply -i /root/cluster.yaml

# wait until all OSDs are deployed
for i in ${osd_nodes[@]%%.*}
do
    while [ ! "$(ceph osd tree --format=json | jq -r '.nodes[] | .name, .status'  \
               | grep -v default \
               | sed 's/null//g' \
               | tr '\n' ' ' \
               | awk "/$i/ && /osd./ && ! /down/{print \$0}")" ]
    do
        sleep 60
    done

done

ceph -s
