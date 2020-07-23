set -ex

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
    if [ ! -z "$(ceph crash ls)" ]; then
        ceph crash archive-all
    fi

    until [ "$(ceph health)" == "HEALTH_OK" ]
    do
    	sleep 30
    done
}

# get storage minion
osd_nodes=($osd_nodes)
storage_minion=${osd_nodes[0]}

# get storage device name and partition
storage_device_partition=$(ssh $storage_minion "pvdisplay | grep -B 1 \"VG Name .* ceph\" | head -1 | cut -d / -f 3")
storage_device_name=$(echo $storage_device_partition | tr -d [:digit:])

ssh $storage_minion -tt << EOT
mkdir /debug
mount -t debugfs nodev /debug/
cd /debug/fail_make_request
echo 10 > interval 
echo 100 > probability
echo -1 > times
echo 1 > /sys/block/$storage_device_name/make-it-fail
systemctl restart ceph.target
exit
EOT

ceph osd pool create diskfaultinjection $pg_num $pgp_num

ceph osd tree

sleep 30 

(ceph -s | grep ".* osds down" && echo "Failed device recognized by Ceph") || (echo "NOT recognized by Ceph" && exit 1)

failed_osd="$(ceph health detail --format json | jq -r .checks.OSD_DOWN.detail[].message | awk '{print $1}')"

while [ "$(echo $failed_osd | wc -l)" -gt "1" ];do
    sleep 30
    failed_osd="$(ceph health detail --format json | jq -r .checks.OSD_DOWN.detail[].message | awk '{print $1}')"
done

health_ok

# bring device back to healthy state
ssh $storage_minion -tt << EOT
umount /debug
echo 0 > /sys/block/$storage_device_name/make-it-fail
systemctl reset-failed ceph-$(ceph fsid)@${failed_osd}.service
systemctl start ceph-$(ceph fsid)@${failed_osd}.service
exit
EOT

health_ok

ceph osd pool rm diskfaultinjection diskfaultinjection --yes-i-really-really-mean-it
