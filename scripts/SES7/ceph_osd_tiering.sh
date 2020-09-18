set -ex

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
if [ "$(arch)" == "aarch64" ]; then
    count=5
else
    count=100
fi

### Creating pool for cold storage ###
ceph osd pool create cold-storage $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

### Creating pool for hot storage ###
ceph osd pool create hot-storage $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

### Creating tiering ###
ceph osd tier add cold-storage hot-storage
ceph osd tier cache-mode hot-storage writeback
ceph osd tier set-overlay cold-storage hot-storage

ceph osd pool set hot-storage hit_set_type bloom

ceph osd pool set hot-storage hit_set_count 12
ceph osd pool set hot-storage hit_set_period 14400
ceph osd pool set hot-storage target_max_bytes 1000000000000
ceph osd pool set hot-storage min_read_recency_for_promote 2
ceph osd pool set hot-storage min_write_recency_for_promote 2
ceph osd pool set hot-storage target_max_bytes 1099511627776
ceph osd pool set hot-storage target_max_objects 1000000
ceph osd pool set hot-storage cache_target_dirty_ratio 0.4
ceph osd pool set hot-storage cache_target_dirty_high_ratio 0.6
ceph osd pool set hot-storage cache_target_full_ratio 0.8
ceph osd pool set hot-storage cache_min_flush_age 600
ceph osd pool set hot-storage cache_min_evict_age 1800

### Getting cluster health status ###
ceph health

rbd create -p hot-storage image1 --size 2G
rbd_dev=$(rbd map hot-storage/image1)
parted -s $rbd_dev  unit % mklabel gpt mkpart 1 xfs 0 100
lsblk
mkfs.xfs ${rbd_dev}p1
mount ${rbd_dev}p1 /mnt
dd if=/dev/zero of=/mnt/file.bin count=$count bs=1M status=progress oflag=direct

### Removing tiering ###
umount /mnt
rbdmap unmap-all | true
ceph osd tier cache-mode hot-storage readproxy --yes-i-really-mean-it
rados -p hot-storage ls

rados -p hot-storage cache-flush-evict-all | true

while [ $(rados -p hot-storage ls | grep -v "rbd_header" | wc -l) -ge 1 ]
do 
    sleep 15
done

ceph osd tier remove-overlay cold-storage
ceph osd tier remove cold-storage hot-storage

### Removing pools ###
ceph osd pool rm hot-storage hot-storage --yes-i-really-really-mean-it
ceph osd pool rm cold-storage cold-storage --yes-i-really-really-mean-it

sleep 30

ceph -s
