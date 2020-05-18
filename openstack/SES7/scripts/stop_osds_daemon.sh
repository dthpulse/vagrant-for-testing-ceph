set -ex

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
random_minion_fqdn=${osd_nodes[0]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
random_osd=$(ceph osd tree | grep -A 1 $random_minion | grep -o osd.* | grep -v "down" | awk '! /'$random_minion'/{print $1}')
ceph_id=$(ceph fsid)

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


echo "### Getting second random minion and OSD to stop OSD on ###"
random_minion2_fqdn=${osd_nodes[1]}
random_minion2=$(echo $random_minion2_fqdn | cut -d . -f 1)
random_osd2=$(ceph osd tree | grep -A 1 $random_minion2 | grep -o osd.* | grep -v "down" | awk '! /'$random_minion2'/{print $1}')
 
ssh $random_minion2_fqdn "systemctl stop ceph-${ceph_id}@${random_osd2}.service"

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

echo "### Starting previously stopped OSDs ###"
ssh $random_minion_fqdn "systemctl start ceph-${ceph_id}@${random_osd}.service"
ssh $random_minion2_fqdn "systemctl start ceph-${ceph_id}@${random_osd2}.service"

echo "### Removing pool ###"
ceph osd pool rm stoposddeamon stoposddeamon --yes-i-really-really-mean-it

