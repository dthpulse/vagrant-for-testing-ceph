set -ex

echo "
############################################
######  ses6_disk_fault_injection.sh  ######
############################################
"

. /tmp/config.conf

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)
num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

function power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num


function health_ok() {
    until [ "$(ceph health)" == "HEALTH_OK" ]
    do
    	sleep 30
    done
}

# get storage minion
storage_minion=$(salt-run select.minions roles=storage | head -1 | awk '{print $2}')

# get storage device name and partition
storage_device_partition=$(ssh $storage_minion "pvdisplay | grep -B 1 \"VG Name .* ceph\" | head -1 | cut -d / -f 3")
storage_device_name=$(echo $storage_device_partition | tr -d [:digit:])

ssh $storage_minion -tt << EOT
mkdir /debug
mount debugfs /debug -t debugfs
cd /debug/fail_make_request
echo 10 > interval 
echo 100 > probability
echo -1 > times
echo 1 > /sys/block/$storage_device_name/make-it-fail
systemctl restart ceph-osd.target
exit
EOT

ceph osd pool create diskfaultinjection $pg_num $pgp_num

sleep 30

ceph health | grep "HEALTH_OK"

ceph osd tree

sleep 30 

(ceph -s | grep ".* osds down" && echo "Failed device recognized by Ceph") || (echo "NOT recognized by Ceph" && exit 1)

health_ok

# bring device back to healthy state
ssh $storage_minion -tt << EOT
umount /debug
echo 0 > /sys/block/$storage_device_name/$storage_device_partition/make-it-fail
systemctl restart ceph-osd.target
exit
EOT

health_ok

ceph osd pool rm diskfaultinjection diskfaultinjection --yes-i-really-really-mean-it
