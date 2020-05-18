#!/bin/bash

test -z $1 && echo "parameter must be project Vagrantfile" && exit 1

project_name=$(basename `pwd`)
default_libvirt_pool_path="$(virsh pool-dumpxml default | grep path | sed 's/<path>//; s/<\/path>//')"

vm_list=$(virsh list --all --name | grep $project_name)

test -z "$vm_list" && echo "no VMs found for this project" && exit

echo "$vm_list"

echo

#read -p "Do you really want to destroy all these machines? (y/N): " destroy_confirm

destroy_confirm="y"

case $destroy_confirm in 
	y|Y) virsh list --all --name | grep $project_name | xargs -I {} virsh destroy {}
	     virsh list --all --name | grep $project_name | xargs -I {} virsh undefine {} --nvram
	     rm -f ${default_libvirt_pool_path}/${project_name}_*
	     systemctl restart libvirtd
	     VAGRANT_VAGRANTFILE=$1 vagrant destroy -f
             ;;
        ''|*) echo "exiting ..."; exit
             ;;
esac
