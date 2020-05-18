set -ex

cat <<EEF > /srv/pillar/top.sls
base:
  '*':
    - ceph-salt
EEF
touch /srv/pillar/ceph-salt.sls
chown -R salt:salt /srv/pillar
sleep 30
salt \* saltutil.pillar_refresh

monitors=($monitors)
osd_nodes=($osd_nodes)

ceph-bootstrap config "/Cluster/Minions add *"
for monitor in ${monitors[@]}
do
    ceph-bootstrap config "/Cluster/Roles/Mon add $monitor"
    ceph-bootstrap config "/Cluster/Roles/Mgr add $monitor"
done

ceph-bootstrap config "/SSH generate"
ceph-bootstrap config "/Time_Server/Server_Hostname set $master"
ceph-bootstrap config "/Time_Server/External_Servers add ntp.suse.cz"
ceph-bootstrap config "/Containers/Images/ceph set registry.suse.de/suse/sle-15-sp2/update/products/ses7/milestones/containers/ses/7/ceph/ceph"
ceph-bootstrap config ls

salt '*' saltutil.sync_all

sleep 5

systemctl restart salt-master

while [ "$(systemctl is-active salt-master)" != "active" ]
do
    sleep 5
done

#while [ "$(ss -4 state listening sport 4505' | awk '/tcp/{print $4}')" != "0.0.0.0:4505" ]
##while [ "$(ss -4 state listening '( sport 4505 or sport 4506 )' | awk '/tcp/{print $4}'  | tr '\n' ' ')" != "0.0.0.0:4505 0.0.0.0:4506 " ]
#do
#    sleep 5
#done

sleep 60

ceph-bootstrap -l debug --log-file=/var/log/ceph-bootstrap.log deploy --non-interactive
