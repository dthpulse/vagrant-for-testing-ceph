set -ex

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)

k=4
m=2

num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
size=$(ceph-conf -c /dev/null -D | grep "osd_pool_default_size" | cut -d = -f 2 | sed 's/\ //g')
osd_num=$(ceph osd ls | wc -l)
recommended_pg_per_osd=100
pg_num=$(power2 $(echo "(($osd_num*$recommended_pg_per_osd) / $size) / ($num_of_existing_pools + $num_of_pools)" | bc))
pgp_num=$pg_num


pg_size_total=$(($pg_num*($k+$m)))
until [ $pg_size_total -lt $((200*$num_of_osd)) ]
do
 pg_num=$(($pg_num/2))
 pgp_num=$pg_num
 pg_size_total=$(($pg_num*($k+$m)))
done

function print_cmd() {
    echo
    echo "\$bash > $@"
    echo
    $@
    echo
}

. /tmp/config.conf

echo "
###################################
######  ses_replace_disk.sh  ######
###################################
"

echo "### Getting random minion and its random OSD ###"
random_minion_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
random_osd=$(ceph osd tree | grep -A 1 $random_minion | grep -o "osd\.".* | awk '{print$1}')
osd_id=$(echo $random_osd | cut -d . -f 2)
minion_osd_device=$(salt "$random_minion_fqdn" cmd.run "find /var/lib/ceph/osd/ceph-$osd_id -type l -name block -exec readlink {} \; | rev | cut -d / -f 1 | rev | xargs -I {} readlink /dev/disk/by-partuuid/{} | tr -d [:punct:],[:digit:]" --output txt | cut -d : -f 2 | tr -d ' ')

print_cmd ceph osd pool create replacedisk $pg_num $pgp_num

print_cmd salt-run disengage.safety >/dev/null 2>&1

print_cmd salt-run replace.osd $osd_id

print_cmd salt $random_minion_fqdn osd.update_destroyed /dev/$minion_osd_device $osd_id

print_cmd salt-run disengage.safety >/dev/null 2>&1

print_cmd salt-run replace.osd $osd_id

print_cmd ceph osd rm $osd_id

print_cmd ceph osd crush remove $random_osd

print_cmd ceph osd tree

print_cmd ceph health detail

if [ $(salt $random_minion_fqdn cmd.run "lsblk -o KNAME | grep $minion_osd_device | wc -l" --output txt | cut -d : -f 2) -gt 1 ]
then 
    echo "Error: Minion device still has some partitions"
    exit 1
else
    echo "Device is properly cleaned"
fi


echo "Adding new device to OSD"
print_cmd salt-run state.orch ceph.stage.1 2>/dev/null
print_cmd salt-run state.orch ceph.stage.2 2>/dev/null
print_cmd salt-run state.orch ceph.stage.3 2>/dev/null

print_cmd ceph health detail

print_cmd ceph osd tree

if [ $(salt $random_minion_fqdn cmd.run "lsblk -o KNAME | grep $minion_osd_device | wc -l" --output txt | cut -d : -f 2) -gt 1 ]
then 
    salt $random_minion_fqdn cmd.run "lsblk -f"
else
    echo "Device is not an OSD"
    exit 1
fi

print_cmd ceph osd pool rm replacedisk replacedisk --yes-i-really-really-mean-it
