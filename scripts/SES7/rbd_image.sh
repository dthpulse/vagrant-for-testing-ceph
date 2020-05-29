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
ceph osd pool create pera $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Creating image in the pool ###"
rbd create pera/brdo --size 102400 --object-size 10000
rbd create pera/myimage_100 --size 102400

echo "### Getting pool size ###"
rados df pera

echo "### Listing pool content ###"
rados -p pera ls

sleep 10

echo "### Checking cluster health status ###"
ceph -s

echo "### Enabling application on pool ###"
ceph osd pool application enable pera rbd 

sleep 3

ceph -s

ceph osd pool rename pera czechia

ceph osd pool ls | grep czechia

echo "### Removing pool 'pera'"
ceph osd pool rm czechia czechia --yes-i-really-really-mean-it
