set -ex

### Getting Ceph health
echo "ceph health"
ceph health
echo "ceph -s"
ceph -s
