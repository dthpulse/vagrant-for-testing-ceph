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

# testing part

echo "### Getting cluster health status"
ceph -s

echo "### Tracing 'ceph' command"
#echo quit | strace -c ceph

echo "### Getting minion to make tests on"
osd_nodes=($osd_nodes)
minion2run=${osd_nodes[0]}

echo "### Stopping and starting ceph.target on minion"
ssh $minion2run "systemctl status ceph.target"
ssh $minion2run "systemctl stop ceph.target"
sleep 15
ssh $minion2run "systemctl start ceph.target"
sleep 15
ssh $minion2run "systemctl status ceph.target"

sleep 30

echo "### Getting cluster health status"
ceph -s

echo "### Restarting ceph.target on minion"
ssh $minion2run "systemctl status ceph.target"
ssh $minion2run "systemctl restart ceph.target"
ssh $minion2run "systemctl status ceph.target"

sleep 30

echo "### Getting cluster health status"
ceph -s

echo "### Listing pools"
ceph osd lspools

echo "### Creating pool"
ceph osd pool create testpool1 $pg_num $pgp_num replicated
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Listing pools with 'rados' command"
rados lspools

echo "### Getting monitors status"
ceph mon stat

echo "### Getting OSDs status"
ceph osd stat

echo "### Getting OSD tree"
ceph osd tree

echo "### Removing pool"
ceph osd pool rm testpool1 testpool1 --yes-i-really-really-mean-it

sleep 10

echo "### Getting cluster health status"
ceph -s

