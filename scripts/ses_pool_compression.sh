set -ex

. /tmp/config.conf

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

print_cmd() {
	echo
	echo "\$bash > $@"
	echo
	$@
	echo
}

for mode in passive aggressive force
do 

	print_cmd ceph osd pool create pool_${mode} $pg_num $pgp_num

	while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

	print_cmd ceph osd pool application enable pool_${mode} rbd

	print_cmd ceph osd pool set pool_${mode} compression_algorithm zlib
	print_cmd ceph osd pool set pool_${mode} compression_mode $mode

	print_cmd rbd create -p pool_${mode} image1 --size 5G

	print_cmd rbd du -p pool_${mode} image1

	print_cmd modprobe rbd

	rbd_dev=$(rbd map pool_${mode}/image1)

        print_cmd parted $rbd_dev mklabel gpt

	print_cmd parted $rbd_dev unit % mkpart 1 xfs 0 100

	print_cmd mkfs.xfs ${rbd_dev}p1

	print_cmd mkdir /mnt/pool_$mode

	print_cmd mount ${rbd_dev}p1 /mnt/pool_$mode

	print_cmd dd if=/dev/zero of=/mnt/pool_$mode/file.bin bs=2M count=2048 status=progress oflag=direct

	print_cmd rbd du -p pool_${mode} image1

	print_cmd umount /mnt/pool_$mode

	print_cmd rbd unmap ${rbd_dev}


	print_cmd ceph osd pool rm pool_$mode pool_$mode --yes-i-really-really-mean-it

	while [ $(ceph -s | grep creating -c) -gt 0 ]; do echo -n .;sleep 1; done

	print_cmd ceph -s

done

