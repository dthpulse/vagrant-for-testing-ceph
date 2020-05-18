set -ex

echo "
#######################################
######  ses_ceph_osd_tiering.sh  ######
#######################################
"

. /tmp/config.conf

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)
num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=2

function power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num

# testing part

echo "### Creating pool for cold storage ###"
ceph osd pool create cold-storage $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Creating pool for hot storage ###"
ceph osd pool create hot-storage $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Creating tiering ###"
ceph osd tier add cold-storage hot-storage
ceph osd tier cache-mode hot-storage writeback
ceph osd tier set-overlay cold-storage hot-storage

ceph osd pool set hot-storage hit_set_type bloom

ceph osd tier cache-mode hot-storage forward || true
ceph osd tier cache-mode hot-storage forward --yes-i-really-mean-it

echo "### Getting cluster health status ###"
ceph health | grep "HEALTH_OK"

echo "### Removing tiering ###"
ceph osd tier cache-mode hot-storage none
ceph osd tier remove-overlay cold-storage
ceph osd tier remove cold-storage hot-storage

echo "### Removing pools ###"
ceph osd pool rm hot-storage hot-storage --yes-i-really-really-mean-it
ceph osd pool rm cold-storage cold-storage --yes-i-really-really-mean-it

ceph health | grep "HEALTH_OK"

