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

for mode in passive aggressive force
do 

	ceph osd pool create pool_${mode} $pg_num $pgp_num

	while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

	ceph osd pool application enable pool_${mode} rbd

	ceph osd pool set pool_${mode} compression_algorithm zlib
	ceph osd pool set pool_${mode} compression_mode $mode

	rbd create -p pool_${mode} image1 --size 5G

	rbd du -p pool_${mode} image1

	modprobe rbd

	rbd_dev=$(rbd map pool_${mode}/image1)

        parted $rbd_dev mklabel gpt

	parted $rbd_dev unit % mkpart 1 xfs 0 100

	mkfs.xfs ${rbd_dev}p1

	mkdir /mnt/pool_$mode

	mount ${rbd_dev}p1 /mnt/pool_$mode

	dd if=/dev/zero of=/mnt/pool_$mode/file.bin bs=1M count=100 status=progress oflag=direct

	rbd du -p pool_${mode} image1

	umount /mnt/pool_$mode

	rbd unmap ${rbd_dev}


	ceph osd pool rm pool_$mode pool_$mode --yes-i-really-really-mean-it

	while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

	ceph -s

done

