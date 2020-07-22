set -ex

master=$master
osd_nodes=($osd_nodes)
monitors=($monitors)

for pool in testpool newpool;do
    ceph osd pool create $pool 128 128
    ceph osd pool application enable $pool rbd
done

rbd create -p testpool image1 --size=1G

ceph tell mon.* injectargs \
    '--mon_debug_unsafe_allow_tier_with_nonempty_snaps=1'

ceph osd tier add newpool testpool --force-nonempty

ceph osd tier cache-mode testpool writeback

rados -p testpool cache-flush-evict-all

ceph osd tier set-overlay newpool testpool

ceph osd tier remove-overlay newpool

ceph osd tier remove newpool testpool

ceph tell mon.* injectargs \
    '--mon_debug_unsafe_allow_tier_with_nonempty_snaps=0'

rados -p newpool ls | grep image1
