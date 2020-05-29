set -ex

# on master
sed -i '1{/"127.0.0.1"/!d}' /etc/hosts

for node in ${osd_nodes[@]} ${monitors[@]}
do
    ssh $node "sed -i '1{/\"127.0.0.1\"/!d}' /etc/hosts"
done
