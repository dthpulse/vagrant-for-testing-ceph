set -ex


if [ -z "$(salt-run select.minions roles=igw)" ]
then
    storage_minions=($(salt-run select.minions roles=storage | awk '{print $2}'))
    random_minion_fqdn=${storage_minions[$((`shuf -i 0-${#storage_minions[@]} -n 1`-1))]}
    random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
    random_minion_ip=$(nslookup $random_minion | sed '/^$/d; s/ //' | tail -1 | cut -d : -f 2)
  
    echo "role-igw/cluster/${random_minion_fqdn}.sls" >> /srv/pillar/ceph/proposals/policy.cfg
    
    salt-run state.orch ceph.stage.2
    salt-run state.orch ceph.stage.3
    salt-run state.orch ceph.stage.4
  else
    random_minion_fqdn=$(salt-run select.minions roles=igw | awk '{print $2}' | head -1)
    random_minion=$(echo $random_minion_fqdn | cut -d . -f 1)
    random_minion_ip=$(nslookup $random_minion | sed '/^$/d; s/ //' | tail -1 | cut -d : -f 2)
fi

# on igw:
iscsi_iname=$(ssh $random_minion iscsi-iname)
ssh $random_minion "gwcli /iscsi-targets create $iscsi_iname"
ssh $random_minion "sed -i \"s/=.*/=$iscsi_iname/\" /etc/iscsi/initiatorname.iscsi"
HOST=$(curl -s --user admin:admin -X GET http://${random_minion}:5000/api/sysinfo/hostname | jq -r .data)

if [ ! -n "$HOST" ]
then
    echo "ERROR: rbd-target-api is not running on ${random_minion}:5000"
    false
fi

# configure iSCSI GW on random minion
ssh $random_minion -tt << EOF
gwcli /iscsi-targets/$iscsi_iname/gateways create $random_minion_fqdn $random_minion_ip skipchecks=true
gwcli /disks create pool=iscsi-images image=image_1 size=10G
gwcli /iscsi-targets/$iscsi_iname/hosts auth nochap

gwcli ls
targetcli ls

ls -lR /sys/kernel/config/target/
ss --tcp --numeric state listening | grep 3260 || exit 1
set -e
zypper --non-interactive --no-gpg-checks install \
    --force --no-recommends open-iscsi multipath-tools
exit
EOF

# map iSCSI target on clients
declare -a iqn

for client in $(cat /tmp/clients.conf)
do
    iqn=$(ssh $client tail -1 /etc/iscsi/initiatorname.iscsi | cut -d = -f 2)
    
    ssh $random_minion gwcli /iscsi-targets/$iscsi_iname/hosts create $iqn
    ssh $random_minion gwcli /iscsi-targets/$iscsi_iname/hosts/$iqn disk add iscsi-images/image_1
    
    if [ ! -z $(ssh $client which apt) ]
    then
    	ssh $client "apt install -y multipath-tools open-iscsi"
    elif [ ! -z $(ssh $client which yum) ]
    then
    	ssh $client "yum install -y device-mapper-multipath.x86_64 iscsi-initiator-utils.x86_64"
    	ssh $client "find /usr -name multipath.conf -exec cp {} /etc/ \;"
    elif [ ! -z $(ssh $client which zypper) ]
    then
    	ssh $client "zypper in -y multipath-tools open-iscsi"
    fi
    
    
    if [ ! -z $(ssh $client which systemctl) ]
    then
    	ssh $client "systemctl start iscsid"
    elif [ ! -z $(ssh $client ls /etc/init.d/iscsid) ]
    then 
    	ssh $client "/etc/init.d/iscsid start"
    fi
    
    ssh $client -tt << EOF
        iscsiadm -m discovery -t st -p $random_minion_ip
        iscsiadm -m node -L all
        iscsiadm -m session -P3
        
        sleep 5
        
        ls -l /dev/disk/by-path
        ls -l /dev/disk/by-*id
        iscsi_dev=/dev/disk/by-path/*${random_minion_ip}*iscsi*
        if ( mkfs -t xfs \$iscsi_dev ) ; then
            : 
        else
            dmesg
            false
        fi
        test -d /mnt
        
        mount \$iscsi_dev /mnt || exit 1
        df -h /mnt
        touch /mnt/$client
        test -s /mnt/$client
        ls -l /mnt/
        umount /mnt
        
        if [ ! -z \`eval "which systemctl"\` ]
        then
          systemctl start multipathd.service
          systemctl --no-pager --full status multipathd.service
        else
          /etc/init.d/multipathd start
        fi
        
        sleep 5
        if [ -s /etc/multipath/wwids ] && [ -z \`grep -v ^# /etc/multipath/wwids\` ]
        then
        test -s /etc/multipath.conf || multipath -t > /etc/multipath.conf
        systemctl restart multipathd || /etc/init.d/multipathd restart
        multipath -v3 -d 2>&1 | grep "not in wwids file" | grep -Po '(?<=(wwid )).*(?= not)' | xargs multipath -a
        systemctl restart multipathd || /etc/init.d/multipathd restart
        fi
        multipath -ll  # to show multipath information
        sleep 10
        mp_dev=/dev/mapper/\`multipath -ll | head -1 | sed 's/\(\w\+\).*/\1/g'\`
        mount \$mp_dev /mnt || exit 1
        df -h /mnt
        test -s /mnt/$client
        touch /mnt/${client}_mp
        test -s /mnt/${client}_mp
        ls -l /mnt
        umount /mnt
        
        iscsiadm -m node --logout
        iscsiadm -m discovery -t st -o delete -p $random_minion_ip
        exit
EOF
    
    if [ $(echo $?) -ne 0 ]
    then
    	ssh $client -tt << EOF
            iscsiadm -m node --logout
            iscsiadm -m discovery -t st -o delete -p $random_minion_ip
            exit
EOF
    fi

done


