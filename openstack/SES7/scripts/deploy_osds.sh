set -ex

osd_nodes=($osd_nodes)

ceph orchestrator status

ceph orchestrator device ls

ceph orchestrator service ls

for osd_node in ${osd_nodes[@]}
do
    ceph orchestrator host add $osd_node
    ceph orchestrator device ls $osd_node | awk '/True/ {print $2}' | xargs -I {} ceph orchestrator osd create ${osd_node}:{}
done

### bootstrap don't know to run jobs in parallel
#for osd_node in ${osd_nodes[@]}
#do
#    ceph orchestrator host add $osd_node &
# #   ceph orchestrator device ls $osd_node | awk '/True/ {print $2}' | xargs -I {} ceph orchestrator osd create ${osd_node}:{}
#done
#
#wait
#
#for osd_node in ${osd_nodes[@]}
#do
##    ceph orchestrator host add $osd_node
#    ceph orchestrator device ls $osd_node | awk '/True/ {print $2}' | xargs -I {} ceph orchestrator osd create ${osd_node}:{} &
#done
#
#wait

exit
