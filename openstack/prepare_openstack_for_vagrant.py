#!/usr/bin/env python

import sys
import subprocess
import yaml
import shutil
import os
import getopt

def printhelp():
    print 'prepare_openstack_for_vagrant.py -y <yamlfile> -f <vagrantfile>'
    print 'prepare_openstack_for_vagrant.py -y <yamlfile> -f <vagrantfile> --delete-servers' + ' // Delete servers only.'
    print 'prepare_openstack_for_vagrant.py -y <yamlfile> -f <vagrantfile> --delete-volumes' + ' // Delete volumes only.'
    return

def main(argv):
    yamlfile = ''
    vagrantfile = ''
    try:
        opts, args = getopt.getopt(argv,"hy:f:",["yamlfile=","vagrantfile=","delete-servers","delete-volumes"])
    except getopt.GetoptError:
        printhelp()
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h' or opt == '':
            printhelp()
            sys.exit()
        elif opt in ("-y", "--yamlfile"):
            yamlfile = arg
        elif opt in ("-f", "--vagrantfile"):
            vagrantfile = arg
    if not opts:
        printhelp()
        sys.exit(2)

# yaml file to use
    document = open(yamlfile, 'r')
    
    parsed = yaml.load(document, Loader=yaml.FullLoader)
    
# find volume name in yaml file
    volumes_to_create = parsed["osd_node"]["number"] * parsed["osd_node"]["osds_number"]
    volume_size = parsed["osd_node"]["osd_size"]
    
# find nodes hostname in yaml file 
    nodes_to_create = [parsed["master"]["hostname"]]

# separate device for DB
    db_devices = parsed["osd_node"]["db_device"]
    if db_devices is True:
        db_volume_size = 2 * volume_size + 5

# add number to nodes hostname
    for i in range(1, parsed["osd_node"]["number"] + 1):
        nodes_to_create.append(parsed["osd_node"]["hostname"] + str(i))
    
# add number to monitor hostname
    for i in range(1, parsed["monitor"]["number"] + 1):
        nodes_to_create.append(parsed["monitor"]["hostname"] + str(i))
    
# if clients are defined in yaml add them to nodes_to_create list
    if parsed["clients"] is None:
        print "Clients not defined"
    else:
        for i in  parsed["clients"]:
            nodes_to_create.append(i)
    
# print what nodes are going to be created
# print "*** Going to create these servers on OpenStack: " + " ".join(str(x) for x in nodes_to_create)
    
# check if nodes we defined in yaml exists on OpenStack
# if they exists we are going to delete them
    openstack_server_list = subprocess.check_output("openstack server list", stderr=subprocess.STDOUT, shell=True)
    for node in range(0, len(nodes_to_create)):

        if opt in "--delete-volumes":
            break

        print "*** Checking if " + nodes_to_create[node] + " exists on OpenStack ***"
        if nodes_to_create[node] in openstack_server_list.split():
            print "Deleting server " + nodes_to_create[node]
            subprocess.call("openstack server delete " + nodes_to_create[node], shell=True)
            if os.path.isdir('./.vagrant'):
                shutil.rmtree('./.vagrant')
            if os.path.isdir('./' + vagrantfile + '-files'):
                shutil.rmtree('./' + vagrantfile + '-files')
        else:
            print "Didn't find server " + nodes_to_create[node] + " on OpenStack"

    if opt in "--delete-servers":
        sys.exit()
    
# check if volumes we defined in yaml exists on OpenStack
# if they exists we are going to delete them and create new ones
    openstack_volume_list = subprocess.check_output("openstack volume list", stderr=subprocess.STDOUT, shell=True)
    for volume in range(1, volumes_to_create + 1):
        print "*** Checking if vgr_volume" + str(volume) + " exists on OpenStack ***"
        if "vgr_volume" + str(volume) in openstack_volume_list.split():
            print "Deleting volume vgr_volume" + str(volume)
            subprocess.call("openstack volume delete vgr_volume" + str(volume), shell=True)

            if opt not in "--delete-volumes":
                print "Creating volume vgr_volume" + str(volume)
                subprocess.call("openstack volume create --size " + str(volume_size) + " vgr_volume" + str(volume) , shell=True)
        else:
            if opt not in "--delete-volumes":
                print "Didn't find volume vgr_volume" + str(volume) + " on OpenStack. Going to create it."
                subprocess.call("openstack volume create --size " + str(volume_size) + " vgr_volume" + str(volume) , shell=True)

    if db_devices is True:
        db_devices_to_create = parsed["osd_node"]["number"]
        for vgr_db_volume in range(1, db_devices_to_create + 1):
            print "*** Checking if vgr_db_volume" + str(vgr_db_volume) + " exists on OpenStack ***"
            if "vgr_db_volume" + str(vgr_db_volume) in openstack_volume_list.split():
                print "Deleting volume vgr_db_volume" + str(vgr_db_volume)
                subprocess.call("openstack volume delete vgr_db_volume" + str(vgr_db_volume), shell=True)
                if os.path.isdir('./.vagrant'):
                    shutil.rmtree('./.vagrant')
                if os.path.isdir('./' + vagrantfile + '-files'):
                    shutil.rmtree('./' + vagrantfile + '-files')

                if opt not in "--delete-volumes":
                    print "Creating volume vgr_db_volume" + str(vgr_db_volume)
                    subprocess.call("openstack volume create --size " + str(db_volume_size) + " vgr_db_volume" + str(vgr_db_volume), shell=True)
            else:
                if opt not in "--delete-volumes":
                    print "Didn't find volume vgr_db_volume" + str(vgr_db_volume) + " on OpenStack. Going to create it."
                    subprocess.call("openstack volume create --size " + str(db_volume_size) + " vgr_db_volume" + str(vgr_db_volume) , shell=True)

if __name__ == "__main__":
    main(sys.argv[1:])
