set -ex

ceph config set global osd_pool_default_pg_autoscale_mode off

ceph config set global mon_allow_pool_delete true

ceph config set global mon_clock_drift_allowed 2.0

ceph config set osd debug_ms 1

ceph config set global cluster_network 192.168.122.0/24

ceph config set global public_network 192.168.121.0/24
