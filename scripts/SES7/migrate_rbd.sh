set -ex

master=$master

monitors=($monitors)

osd_nodes=($osd_nodes)

for pool in srcpool tgtpool;do
    ceph osd pool create $pool 128 128
    ceph osd pool application enable $pool rbd
done

rbd create -p srcpool image1 --size=1G

rbd_image=$(rbd map srcpool/image1)

parted -s $rbd_image unit % mklabel gpt mkpart 1 xfs 0 100

mkfs.xfs /dev/rbd0p1

mount ${rbd_image}p1 /mnt

touch /mnt/testfile.txt

umount /mnt

rbd device unmap ${rbd_image}

rbd migration prepare srcpool/image1 tgtpool/newimage

rbd migration execute srcpool/image1

rbd migration commit srcpool/image1

rbd map tgtpool/newimage

lsblk -p | grep ${rbd_image}

mount ${rbd_image}p1 /mnt

ls /mnt/testfile.txt




