set -ex

monitors=($monitors)
osd_nodes=($osd_nodes)

systemctl restart salt-master

if [ "$(arch)" == "x86_64" ]
then
    sleep 240
    ntp_server="ntp.suse.cz"
    registries="add prefix=registry.suse.de location=192.168.122.1:5000 insecure=true"
elif [ "$(arch)" == "aarch64" ]
then
    sleep 660
    ntp_server="ntp.suse.de"
    registries=""
fi

salt \* saltutil.sync_all

sleep 15

ceph-salt config /ceph_cluster/minions add "*"
ceph-salt config /ceph_cluster/roles/cephadm add "*"
ceph-salt config /ceph_cluster/roles/admin add "$master"

ceph-salt config /ceph_cluster/roles/bootstrap set "${monitors[0]}"

for i in ${monitors[@]}
do
    ceph-salt config /ceph_cluster/roles/admin add "$i"
done

ceph-salt config /ssh generate
ceph-salt config /time_server/servers add "$master"
ceph-salt config /time_server/subnet set "192.168.122.0/24"
ceph-salt config /time_server/external_servers add "$ntp_server"
ceph-salt config /cephadm_bootstrap/dashboard/username set admin
ceph-salt config /cephadm_bootstrap/dashboard/password set admin
ceph-salt config /cephadm_bootstrap/dashboard/force_password_update disable
ceph-salt config /containers/registries_conf/registries $registries
ceph-salt config /cephadm_bootstrap/ceph_image_path set "registry.suse.de/suse/sle-15-sp2/update/products/ses7/update/cr/containers/ses/7/ceph/ceph"

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
               | awk "/$i/ && /osd./ && ! /down/{print \$0}")" ] \
          || [  "$(ceph osd tree --format=json | jq -r '.stray[] | .status' | grep down)" ]
    do
        sleep 60
    done

done

ceph -s

ceph mgr module disable dashboard

while [ "$(ceph mgr services --format json | jq -r .dashboard)" != "null" ];do 
    sleep 5
done
