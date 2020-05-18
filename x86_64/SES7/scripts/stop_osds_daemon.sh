set -ex

echo "WWWWW $0 WWWWW"

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)
num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num

# testing part

echo "### Creating pool ###"
ceph osd pool create stoposddeamon $pg_num $pgp_num
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Getting random minion and OSD to stop OSD on ###"

osd_nodes=($osd_nodes)

for node in ${osd_nodes[0]} ${osd_nodes[1]}
do
    random_minion_fqdn="$node"
    random_minion="${random_minion_fqdn%%.*}"
    random_osd=$(ceph osd tree | grep -A 1 $random_minion | awk 'FNR==2{print $4}')
    ceph_id=$(ceph fsid)

    stopped_osds+=($random_osd)
    ssh $random_minion_fqdn "systemctl stop ceph-${ceph_id}@${random_osd}.service"

    sleep 5

    echo "### Checking cluster health ###"
    ceph -s

    until [ "$(ceph health)" == "HEALTH_OK" ]
    do
        let n+=30
        sleep 30
        echo "waiting till health is OK."
    done

    echo "Total waiting time ${n}s."
    unset n
    
    ceph osd tree
    ceph -s
done

echo "### Starting previously stopped OSDs ###"
for i in ${!stopped_osds[@]}
do
    ssh ${osd_nodes[i]} "systemctl start ceph-${ceph_id}@${stopped_osds[i]}.service"
done

echo "### Removing pool ###"
ceph osd pool rm stoposddeamon stoposddeamon --yes-i-really-really-mean-it

