set -ex

create_pool () {
# calculating PG and PGP number
num_of_osd=$(ceph osd ls | wc -l)

k=4
m=2

num_of_existing_pools=$(ceph osd pool ls | wc -l)
num_of_pools=1

power2() { echo "x=l($1)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l; }
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

ceph osd pool create $1 $pg_num $pg_num
ceph osd pool application enable $1 rbd
}

create_pool networkfailure 
pool_name="networkfailure"
rbd -p $pool_name create image1 --size 2G
rbd_device=$(rbd map $pool_name/image1)
parted -s $rbd_device mklabel gpt unit % mkpart 1 xfs 0 100
mkfs.xfs ${rbd_device}p1
mount ${rbd_device}p1 /mnt

function nettest () {
    local test_name=$1
    set +x
    time_consumed+="$test_name - $( (time dd if=/dev/zero  of=/mnt/file1.bin count=100 bs=1M oflag=direct >/dev/null 2>&1) 2>&1 | sed '/^$/d' | head -1); "
    set -x
    ls -l /mnt/file1.bin
    rm -f /mnt/file1.bin
}

function create_netem_rules () {
    local minion_list="$2"
    for minion in $minion_list
    do
        case $1 in 
            delay|delay_all) 
                ssh $minion "tc qdisc add dev $cluster_interface root netem delay 100ms 10ms distribution normal"
                if [ "$public_interface" != "$cluster_interface" ]
                then
                    ssh $minion   "tc qdisc add dev $public_interface root netem delay 100ms 10ms distribution normal"
                fi
                ;;
            packet_loss|packet_loss_all) 
                ssh $minion  "tc qdisc add dev $cluster_interface root netem loss 0.3% 25%"
                if [ "$public_interface" != "$cluster_interface" ]
                then
                    ssh $minion  "tc qdisc add dev $public_interface root netem loss 0.3% 25%"
                fi
                ;;
            packet_dup|packet_dup_all) 
                ssh $minion  "tc qdisc add dev $cluster_interface root netem duplicate 1%"
                if [ "$public_interface" != "$cluster_interface" ]
                then
                    ssh $minion  "tc qdisc add dev $public_interface root netem duplicate 1%"
                fi
                ;;
            packet_corruption|packet_corruption_all) 
                ssh $minion  "tc qdisc add dev $cluster_interface root netem corrupt 0.1%"
                if [ "$public_interface" != "$cluster_interface" ]
                then
                    ssh $minion  "tc qdisc add dev $public_interface root netem corrupt 0.1%"
                fi
                ;;
            packet_reordering|packet_reordering_all) 
                ssh $minion  "tc qdisc add dev $cluster_interface root netem delay 10ms reorder 25% 50%"
                if [ "$public_interface" != "$cluster_interface" ]
                then
                    ssh $minion  "tc qdisc add dev $public_interface root netem delay 10ms reorder 25% 50%"
                fi
                ;;
        esac
    
    done
}

function remove_netem_rules () {
    local minion_list="$1"
    for rm_qdisc_minion in $minion_list
    do
        if [ ! -z $cluster_interface ] && [ "$cluster_interface" != "$public_interface" ]
        then
               ssh $rm_qdisc_minion  "tc qdisc del dev $cluster_interface root netem || true"
        fi
        
        ssh $rm_qdisc_minion  "tc qdisc del dev $public_interface root netem || true"
    done
}

net_storage_minions=($osd_nodes)
net_monitor_minions=($monitors)

half_net_storage_minions=(${net_storage_minions[@]:0:$((${#net_storage_minions[@]} / 2))})
half_net_monitor_minions=(${net_monitor_minions[@]:0:$((${#net_monitor_minions[@]} / 2))})

# get public and cluster network
public_network=$(ceph config dump | awk '/public_network/{print $4}')
cluster_network=$(ceph config dump | awk '/cluster_network/{print $4}')

public_interface=$(ip -o -4 address | grep "${public_network%.*}" | awk '{print $2}' | sed '/^$/d')
cluster_interface=$(ip -o -4 address | grep "${cluster_network%.*}" | awk '{print $2}' | sed '/^$/d')

# healthy network test
nettest "network_healthy"

# PACKET DELAY
# delay on half of osd nodes
create_netem_rules "delay" "${half_net_storage_minions[@]}"
nettest "network_delay_osd_node"
remove_netem_rules "${half_net_storage_minions[@]}"

# delay on half of monitors
create_netem_rules "delay" "${half_net_monitor_minions[@]}"
nettest "network_delay_monitor_nodes"
remove_netem_rules "${half_net_monitor_minions[@]}"

# delay on all osd nodes
create_netem_rules "delay_all" "${net_storage_minions[@]}"
nettest "network_delay_all_osd_nodes"
remove_netem_rules "${net_storage_minions[@]}" 

# delay on all monitors
create_netem_rules "delay_all" "${net_monitor_minions[@]}"
nettest "network_delay_all_monitor_nodes"
remove_netem_rules "${net_monitor_minions[@]}"

# delay on all monitors and osd nodes
create_netem_rules "delay_all" "${net_storage_minions[@]} ${net_monitor_minions[@]}"
nettest "network_delay_on_all_monitors_and_all_osdnodes"
remove_netem_rules "${net_storage_minions[@]} ${net_monitor_minions[@]}"

# PACKET LOSS
# packet loss on half of osd nodes
create_netem_rules "packet_loss" "${half_net_storage_minions[@]}"
nettest "network_packet_loss_osd_node"
remove_netem_rules "${half_net_storage_minions[@]}"

# packet loss on half of monitors
create_netem_rules "packet_loss" "${half_net_monitor_minions[@]}"
nettest "network_packet_loss_monitor_node"
remove_netem_rules "${half_net_monitor_minions[@]}"

# packet loss on all osd nodes
create_netem_rules "packet_loss_all" "${net_storage_minions[@]}"
nettest "network_packet_loss_all_osd_nodes"
remove_netem_rules "${net_storage_minions[@]}"

# packet loss on all monitors
create_netem_rules "packet_loss_all" "${net_monitor_minions[@]}"
nettest "network_packet_loss_all_monitors"
remove_netem_rules "${net_monitor_minions[@]}"

# packet loss on all monitors and osd nodes
create_netem_rules "packet_loss_all" "${net_storage_minions[@]} ${net_monitor_minions[@]}"
nettest "network_packet_loss_on_all_monitors_and_all_osdnodes"
remove_netem_rules "${net_storage_minions[@]} ${net_monitor_minions[@]}"

# PACKET DUPLICATION
# packet duplication on half of osd nodes
create_netem_rules "packet_dup" "${half_net_storage_minions[@]}"
nettest "network_packet_dup_osd_node"
remove_netem_rules "${half_net_storage_minions[@]}"

# packet duplication on half of monitors
create_netem_rules "packet_dup" "${half_net_monitor_minions[@]}"
nettest "network_packet_dup_monitor_node"
remove_netem_rules "${half_net_monitor_minions[@]}"

# packet duplication on all osd nodes
create_netem_rules "packet_dup_all" "${net_storage_minions[@]}"
nettest "network_packet_dup_all_osd_nodes"
remove_netem_rules "${net_storage_minions[@]}"

# packet duplication on all monitors
create_netem_rules "packet_dup_all" "${net_monitor_minions[@]}"
nettest "network_packet_dup_all_monitors"
remove_netem_rules "${net_monitor_minions[@]}"

# packet duplication on all monitors and osd nodes
create_netem_rules "packet_dup_all" "${net_storage_minions[@]} ${net_monitor_minions[@]}"
nettest "network_packet_dup_on_all_monitors_and_all_osdnodes"
remove_netem_rules "${net_storage_minions[@]} ${net_monitor_minions[@]}"

# PACKET CORRUPTION
# packet corruption on half of osd nodes
create_netem_rules "packet_corruption" "${half_net_storage_minions[@]}"
nettest "network_packet_corruption_osd_node"
remove_netem_rules "${half_net_storage_minions[@]}"

# packet corruption on half of monitors
create_netem_rules "packet_corruption" "${half_net_monitor_minions[@]}"
nettest "network_packet_corruption_monitor_node"
remove_netem_rules "${half_net_monitor_minions[@]}"

# packet corruption on all osd nodes
create_netem_rules "packet_corruption_all" "${net_storage_minions[@]}"
nettest "network_packet_corruption_all_osd_nodes"
remove_netem_rules "${net_storage_minions[@]}"

# packet corruption on all monitors
create_netem_rules "packet_corruption_all" "${net_monitor_minions[@]}"
nettest "network_packet_corruption_all_monitors"
remove_netem_rules "${net_monitor_minions[@]}"

# packet corruption on all monitors and osd nodes
create_netem_rules "packet_corruption_all" "${net_storage_minions[@]} ${net_monitor_minions[@]}"
nettest "network_packet_corruption_on_all_monitors_and_all_osdnodes"
remove_netem_rules "${net_storage_minions[@]} ${net_monitor_minions[@]}"

# PACKET REORDERING
# packet reordering on half of osd nodes
create_netem_rules "packet_reordering" "${half_net_storage_minions[@]}"
nettest "network_packet_reordering_osd_node"
remove_netem_rules "${half_net_storage_minions[@]}"

# packet reordering on half of monitors
create_netem_rules "packet_reordering" "${half_net_monitor_minions[@]}"
nettest "network_packet_reordering_monitor_node"
remove_netem_rules "${half_net_monitor_minions[@]}"

# packet reordering on all osd nodes
create_netem_rules "packet_reordering_all" "${net_storage_minions[@]}"
nettest "network_packet_reordering_all_osd_nodes"
remove_netem_rules "${net_storage_minions[@]}"

# packet reordering on all monitors
create_netem_rules "packet_reordering_all" "${net_monitor_minions[@]}"
nettest "network_packet_reordering_all_monitors"
remove_netem_rules "${net_monitor_minions[@]}"

# packet reordering on all monitors and osd nodes
create_netem_rules "packet_reordering_all" "${net_storage_minions[@]} ${net_monitor_minions[@]}"
nettest "network_packet_reordering_on_all_monitors_and_all_osdnodes"
remove_netem_rules "${net_storage_minions[@]} ${net_monitor_minions[@]}"

# print results
echo " *** RESULTS: "
echo $time_consumed | tr ';' '\n'

umount /mnt
rbdmap unmap-all | true
ceph osd pool rm networkfailure networkfailure --yes-i-really-really-mean-it

