#!/usr/bin/env bash 

if [ -z "$1" ] || [ ! -e "$1" ]
then
    echo "missing argument <VAGRANTFILE>"
    exit 1
fi

SECONDS=0

vagrantfile=$1
ses_deploy_scripts=(deploy_ses.sh hosts_file_correction.sh configure_ses.sh)
project=$(basename $PWD)
scripts=$(find scripts -maxdepth 1 -type f ! -name ${ses_deploy_scripts[0]} \
     -and ! -name ${ses_deploy_scripts[1]} -and ! -name ${ses_deploy_scripts[2]} -exec basename {} \;)
ssh_options="-i ~/.ssh/storage-automation -l root"
export PDSH_SSH_ARGS_APPEND="-i ~/.ssh/storage-automation -l root"

mkdir logs 2>/dev/null

function vssh_script () {
    local node=$1
    local script="$2"
    echo "WWWWW $script WWWWW"
    pdsh -S -w $node "find /var/log -type f -exec truncate -s 0 {} \;"
    pdsh -S -w $node "bash /vagrant/scripts/$script"
    script_exit_value=$?
}

function create_snapshot () {
    local nodes="$1"
    local script="$2"
    local ses_cluster="$(echo ${ses_cluster[@]})"
    if [ $script_exit_value -ne 0 ] || [ "$script" == "deployment" ]
    then
        pdsh -S -w ${ses_cluster// /,} "supportconfig" 2>&1 >/dev/null
        mkdir -p logs/${script%%.*} 2>/dev/null
        rpdcp -w ${ses_cluster// /,} /var/log/scc_* logs/${script%%.*}/
        pdsh -w ${ses_cluster// /,} "rm -rf /var/log/scc_*"
        for node in $nodes
        do
            virsh destroy ${project}_${node} 
        done
        for node in $nodes
        do
            virsh snapshot-create-as ${project}_${node} ${script%%.*}
        done
    fi
}

function revert_to_ses () {
    echo "Reverting cluster to snapshot \"deployment\""
    for node in ${ses_cluster[@]%%.*}
    do
        node="${project}_${node}"
        virsh snapshot-revert $node deployment 2>&1 > /dev/null
    done

    for node in ${ses_cluster[@]%%.*}
    do
        node="${project}_${node}"
        virsh start $node
    done

    sleep 30
 
    while [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health" 2>/dev/null)" != "HEALTH_OK" ]
    do
        if [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health detail  --format=json | jq -r .checks.MGR_MODULE_ERROR.summary.message" 2>/dev/null)" == "Module 'dashboard' has failed: Timeout('Port 8443 not free on ::.',)" ]
        then
            ssh $ssh_options ${monitors[0]%%.*} "systemctl restart ceph.target" 2>/dev/null
        fi
        sleep 30
    done
}

VAGRANT_VAGRANTFILE=$vagrantfile vagrant up 

if [ $? -ne 0 ];then exit 1;fi

nodes_list=($(VAGRANT_VAGRANTFILE=$vagrantfile vagrant status | awk '/libvirt/{print $1}'))

source ${vagrantfile}-files/bashrc

monitors=($monitors)
osd_nodes=($osd_nodes)
ses_cluster=(${master} ${monitors[@]} ${osd_nodes[@]})


vssh_script "${monitors[0]}" "configure_ses.sh" 

create_snapshot "$(echo ${nodes_list[@]})" "deployment"


for node in ${nodes_list[@]}
do
    virsh start ${project}_${node}
done

while [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health" 2>/dev/null)" != "HEALTH_OK" ]	 
do
        if [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health detail  --format=json | jq -r .checks.MGR_MODULE_ERROR.summary.message" 2>/dev/null)" == "Module 'dashboard' has failed: Timeout('Port 8443 not free on ::.',)" ]
        then
            ssh $ssh_options ${monitors[0]%%.*} "systemctl restart ceph.target" 2>/dev/null
        fi
    sleep 10
done

if [ ${#scripts[@]} -eq 0 ]
then
    exit
fi

for script in ${scripts[@]}
do
    vssh_script "${monitors[0]%%.*}" "$script"
    create_snapshot "$(echo ${ses_cluster[@]%%.*})" "$script"
    revert_to_ses
done

echo "$SECONDS seconds elapsed in $(basename $0)"
