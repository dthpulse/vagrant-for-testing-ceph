#!/usr/bin/env bash 

TEMP=$(getopt -o h --long "vagrantfile:,ses-only,destroy,destroy-before-deploy,all-scripts,only-script:,existing,only-salt-cluster,vagrant-box:" -n 'build_validation.sh' -- "$@")


if [ $? -ne 0 ]; then echo "Terminating ..." >&2; exit 1; fi

ses_only=false
destroy=false
all_scripts=false
only_script=false
existing=false
only_salt_cluster=false
destroy_b4_deploy=false

function helpme () {
  cat << EOF

  usage: ./build_validation.sh --help
  build_validation.sh [arguments]

  arguments:
    --vagrantfile            VAGRANTFILE
    --ses-only               deploys only SES without running BV test scripts
    --destroy                destroys project (vagrant destroy -f)
    --all-scripts            runs all BV scripts under ./scripts directory
    --only-script            runs only specified script
    --existing               runs BV scripts on existing cluster
    --only-salt-cluster      deploys cluster with salt
    --vagrant-box            vagrant box name
    --destroy-before-deploy  destroys existing cluster before deployment (useful for Jenkins)

EOF
}

eval set -- "$TEMP"

while true
do
    case $1 in
        --vagrantfile) export VAGRANT_VAGRANTFILE=$2; shift 2;;
        --ses-only) ses_only=true; shift;;
        --destroy) destroy=true; shift;;
        --all-scripts) all_scripts=true; shift;;
        --only-script) only_script=true; one_script+=($2); shift 2;;
        --existing) existing=true; shift;;
        --only-salt-cluster) only_salt_cluster=true; shift;;
        --vagrant-box) vagrant_box=$2; shift 2;;
        ----destroy-before-deploy) destroy_b4_deploy=true; shift;;
        --help|-h) helpme; exit;;
        --) shift; break;;
        *) break;;
    esac
done

if [ -z "$VAGRANT_VAGRANTFILE" ]
then
    echo "Missing VAGRANTFILE"
    exit 1
fi

SECONDS=0

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
        if [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health detail  --format=json \
                      | jq -r .checks.MGR_MODULE_ERROR.summary.message" 2>/dev/null)" \
                      == "Module 'dashboard' has failed: Timeout('Port 8443 not free on ::.',)" ]
        then
            ssh $ssh_options ${monitors[0]%%.*} "systemctl restart ceph.target" 2>/dev/null
        fi
        sleep 30
    done
}

function set_variables () {
source ${VAGRANT_VAGRANTFILE}-files/bashrc
monitors=($monitors)
osd_nodes=($osd_nodes)
ses_cluster=(${master} ${monitors[@]} ${osd_nodes[@]})
}

if $destroy
then 
    vagrant destroy -f
    exit
fi

if $destroy_b4_deploy
then
    vagrant destroy -f
fi

if ! $existing
then
    if ! $only_salt_cluster
    then
        sed -i 's/deploy_ses: .*/deploy_ses: true/' ${VAGRANT_VAGRANTFILE}.yaml
    else
        sed -i 's/deploy_ses: .*/deploy_ses: false/' ${VAGRANT_VAGRANTFILE}.yaml
    fi

    if [ -z "$vagrant_box" ]
    then
        echo "Missing --vagrant-box-name parameter"
    else
        sed -i "s/ses_cl_box: .*/ses_cl_box: $vagrant_box/" ${VAGRANT_VAGRANTFILE}.yaml
    fi

    vagrant up 
    
    if [ $? -ne 0 ];then exit 1;fi
 
    set_variables

    nodes_list=($(vagrant status | awk '/libvirt/{print $1}'))
    
    vssh_script "${monitors[0]}" "configure_ses.sh" 
    
    create_snapshot "$(echo ${nodes_list[@]})" "deployment"
    
    for node in ${nodes_list[@]}
    do
        virsh start ${project}_${node}
    done
    
    while [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health" 2>/dev/null)" != "HEALTH_OK" ]	 
    do
            if [ "$(ssh $ssh_options ${monitors[0]%%.*} "ceph health detail  --format=json \
                          | jq -r .checks.MGR_MODULE_ERROR.summary.message" 2>/dev/null)" \
                          == "Module 'dashboard' has failed: Timeout('Port 8443 not free on ::.',)" ]
            then
                ssh $ssh_options ${monitors[0]%%.*} "systemctl restart ceph.target" 2>/dev/null
            fi
        sleep 10
    done
else
    set_variables
fi
    
if $ses_only && ! $all_scripts \
|| $ses_only && ! $only_script \
|| $ses_only && $only_salt_cluster; then 
exit
fi

if $all_scripts
then
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
elif $only_script
then
    for script in ${one_script[@]}
    do
        vssh_script "${monitors[0]%%.*}" "$script"
        create_snapshot "$(echo ${ses_cluster[@]%%.*})" "$script"
        revert_to_ses
    done
fi

echo "$SECONDS seconds elapsed in $(basename $0)"
