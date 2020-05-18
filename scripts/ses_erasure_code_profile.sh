set -ex

echo "
###########################################
######  ses_erasure_code_profile.sh  ######
###########################################
"

. /tmp/config.conf

# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)

k=4
m=2

num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

function power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
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

# testing part

echo "### Creating erasure code profile ###"
ceph osd erasure-code-profile set EC-temp-pool || true
ceph osd erasure-code-profile get EC-temp-pool

echo "### Customizing default EC profile settings ###"
ceph osd erasure-code-profile set EC-temp-pool crush-failure-domain=osd k=$k m=$m || true
ceph osd erasure-code-profile set EC-temp-pool crush-failure-domain=osd k=$k m=$m --force || true

echo "### Getting EC settings ###"
ceph osd erasure-code-profile get EC-temp-pool

echo "### Creating EC pool ###"
ceph osd pool create ECtemppool $pg_num $pgp_num erasure EC-temp-pool
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Listing pools ###"
rados lspools

echo "### Listing content of EC pool ###"
rados -p ECtemppool ls &

echo "### Checking if listing of EC pool content was successful ###"
rados_pid=$!
sleep 10
if [ ! -z "$(ps -ef | grep $rados_pid | grep -v grep)" ]
then
    kill -INT $rados_pid
    logger -t "rados erasure" ERROR: failed to list context of ECtemppool
fi

echo "### Removing EC pool and EC profile ###"
ceph osd pool rm ECtemppool ECtemppool --yes-i-really-really-mean-it
ceph osd erasure-code-profile rm EC-temp-pool

echo "### Creating EC profile for 2nd time ###"
ceph osd erasure-code-profile set EC-temp-pool crush-failure-domain=osd k=$k m=$m --force

echo "### Creating EC pool for 2nd time ###"
ceph osd pool create ECtemppool $pg_num $pgp_num erasure EC-temp-pool
sleep 5
while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

echo "### Listing content of EC pool ###"
rados -p ECtemppool ls &

echo "### Checking if listing of EC pool content was successful ###"
rados_pid=$!
sleep 10
if [ ! -z "$(ps -ef | grep $rados_pid | grep -v grep)" ]
then
    kill -INT $rados_pid
    logger -t "rados erasure" ERROR: failed to list context of ECtemppool
fi

echo "### Removing EC pool and EC profile ###"
ceph osd pool rm ECtemppool ECtemppool --yes-i-really-really-mean-it
ceph osd erasure-code-profile rm EC-temp-pool

echo "### Checking cluster health ###"
ceph -s

