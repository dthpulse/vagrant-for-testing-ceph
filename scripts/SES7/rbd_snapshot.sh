set -ex

master=$master
osd_nodes=($osd_nodes)
monitors=($monitors)

function map_rbd () {
    local image="$1"
    rbd_device=$(rbd map rbdpool/$image)
    if [ "$(lsblk -o FSTYPE $rbd_device | tail -1)" != "xfs" ]; then
        mkfs.xfs $rbd_device
    fi
    mount $rbd_device /mnt
}

function snapshot_check () {
    local snapshots=($1)
    rbd snap ls rbdpool/image1 | egrep "$(echo ${snapshots[*]} | sed 's/\ /|/g')"
}

function snapshot_rm () {
    local pool=$1
    local image=$2
    local snapshot=$3
    rbd snap rm $pool/$image@$snapshot | true
}

ceph osd pool create rbdpool 128 128

ceph osd pool application enable rbdpool rbd

rbd create -p rbdpool image1 --size=1G

rbd resize --size=2G rbdpool/image1

map_rbd "image1"
 
echo "myfile" > /mnt/myfile.txt

sleep 5

snapshots=(myfile snap1 snap2)

for i in ${snapshots[*]};do
    rbd snap create rbdpool/image1@$i
done

snapshot_check "${snapshots[*]}"

rm -f /mnt/myfile.txt

umount /mnt

rbd device unmap $rbd_device

rbd snap rollback rbdpool/image1@myfile

map_rbd "image1"

cat /mnt/myfile.txt | grep myfile

snapshot_rm "rbdpool" "image1" "myfile"

rbd snap purge rbdpool/image1

snapshot_check "${snapshots[*]/myfile}"

rbd snap create rbdpool/image1@snapprotect

rbd snap protect rbdpool/image1@snapprotect

snapshot_check "snapprotect"

snapshot_rm "rbdpool" "image1" "snapprotect"

rbd clone rbdpool/image1@snapprotect rbdpool/image2

map_rbd "image2"

umount /mnt

mount $rbd_device

cat /mnt/myfile.txt | grep "myfile"

snapshot_check "snapprotect"

rbd children rbdpool/image1 | grep image2

rbd flatten rbdpool/image2

rbd snap unprotect rbdpool/image1@snapprotect

snapshot_rm "rbdpool" "image1" "snapprotect"
