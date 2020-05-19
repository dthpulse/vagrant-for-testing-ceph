## Table of Contents

[//]: # (To generate a new TOC, first install https://github.com/ekalinin/github-markdown-toc)
[//]: # (and then run "gh-md-toc README.md")
[//]: # (the new TOC will appear on stdout: the expectation is that the maintainer will do the rest.)

* [Vagrant SES build validation](#vagrant-ses-build-validation)
    * [Set-up Vagrang server](#set-up-vagrang-server)
       * [Requiered packages](#requiered-packages)
       * [Install SUSE certificate](#install-suse-certificate)
       * [Configure QEMU to run processes as root user](#configure-qemu-to-run-processes-as-root-user)
       * [Changing Libvirt default pool location](#changing-libvirt-default-pool-location)
       * [Enable vagrant-libvirt network autostart](#enable-vagrant-libvirt-network-autostart)
       * [Enable symbolic links in Apache DocumentRoot](#enable-symbolic-links-in-apache-documentroot)
       * [Create repo files and repo directories](#create-repo-files-and-repo-directories)
       * [Enable and start services:](#enable-and-start-services)
       * [Firewall](#firewall)
       * [SSH keys](#ssh-keys)
       * [Setting up Docker registry cache](#setting-up-docker-registry-cache)
       * [Change Vagrant home directory location](#change-vagrant-home-directory-location)
       * [NFS Server settings](#nfs-server-settings)
       * [Additional server configuration for testing SES cluster with mixed architecture](#additional-server-configuration-for-testing-ses-cluster-with-mixed-architecture)
    * [Preparing for Build Validation tests](#preparing-for-build-validation-tests)
       * [Creating Vagrant Box](#creating-vagrant-box)
          * [Download and mount ISOs](#download-and-mount-isos)
          * [QEMU VM installation for Vagrant box with autoyast file](#qemu-vm-installation-for-vagrant-box-with-autoyast-file)
             * [x86_64](#x86_64)
             * [AARCH64 and Mixed](#aarch64-and-mixed)
          * [QEMU VM installation for Vagrant box manually](#qemu-vm-installation-for-vagrant-box-manually)
             * [x86_64](#x86_64-1)
             * [AARCH64 and Mixed](#aarch64-and-mixed-1)
          * [QEMU VM installation for Vagrant box Clients](#qemu-vm-installation-for-vagrant-box-clients)
          * [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)
    * [Vagrant with OpenStack](#vagrant-with-openstack)
       * [Preparing for Build Validation test with OpenStack](#preparing-for-build-validation-test-with-openstack)
          * [Creating OpenStack image](#creating-openstack-image)
    * [Running Build Validation tests](#running-build-validation-tests)
       * [Build Validation on x86_64, AARCH64 and Mixed](#build-validation-on-x86_64-aarch64-and-mixed)
          * [Running tests with build validation script](#running-tests-with-build-validation-script)
          * [Running tests just with Vagrant](#running-tests-just-with-vagrant)
          * [Destroying project on AARCH64 or Mixed](#destroying-project-on-aarch64-or-mixed)
       * [Running tests on OpenStack](#running-tests-on-openstack)

## Vagrant SES build validation

Using native Vagrant files to build cluster with SES and running build validaion on it.

### Set-up Vagrang server

#### Requiered packages

You'll need following to have installed on your OpenSuse server:

  - Libvirt
 
  - QEMU

  - NFS Server
 
  - Docker

  - Apache 
 
  - vagrant

  - virt-install package

  - pdsh (if you going to trigger build validation with *build_validation.sh*)

  ```bash
  zypper in vagrant docker apache2 patterns-server-kvm_server
  ``` 

  - [vagrant-hostsupdater plugin](https://github.com/cogitatio/vagrant-hostsupdater)

  - [vagrant-libvirt plugin](https://github.com/vagrant-libvirt/vagrant-libvirt)

  ```bash
  vagrant plugin install vagrant-hostsupdater
  vagrant plugin install vagrant-libvirt
  ```

#### Install SUSE certificate

Go to http://download.suse.de/ibs/SUSE:/CA/ and choose distro you are running.

Add it to repositories (Tumbleweed in our case) and install SUSE CA

```
zypper ar -f http://download.suse.de/ibs/SUSE:/CA/openSUSE_Tumbleweed/SUSE:CA.repo
zypper in -y ca-certificates-suse
```

#### Configure QEMU to run processes as root user

*/etc/libvirt/qemu.conf*

```bash
user = root
group = root
```

#### Changing Libvirt default pool location
 In this setup we prefer Libvirt to use default pool location on separate disk / mountpoint as is its default. If another disk is available on your server then mount it under */qemu* . Ohterwise you can use Libvirt default settings unless you created separate partition for */qemu*. 


```bash
mkdir -p /qemu/pools/default
virsh pool-destroy default
virsh pool-undefine default
virsh pool-create-as --name default --type dir --target /qemu/pools/default
virsh pool-dumpxml default > /tmp/default
virsh pool-define --file /tmp/default
virsh pool-autostart default
```

#### Enable vagrant-libvirt network autostart

We prefer Libvirt network *vagratn-libvirt* to start automatically

```bash
virsh net-autostart vagrant-libvirt
```

#### Enable symbolic links in Apache DocumentRoot

*/etc/apache2/default-server.conf*

add *FollowSymLinks* into the Options

```bash
<Directory "/srv/www/htdocs">
  Options FollowSymLinks
  AllowOverride None
  <IfModule !mod_access_compat.c>
      Require all granted
  </IfModule>
  <IfModule mod_access_compat.c>
      Order allow,deny
      Allow from all
  </IfModule>
</Directory>
```  

#### Create repo files and repo directories

Create directories under Apache DocumentRoot:

```
mkdir /srv/www/htdocs/current_os
mkdir /srv/www/htdocs/current_ses
```

Create repo files under Apache DocumentRoot:

Our libvirt NIC IP is 192.168.122.1

```
ip addr show  virbr0
```

curretn_os.repo file:

```
# cat /srv/www/htdocs/current_os.repo 
[basesystem]
name=basesystem
type=rpm-md
baseurl=http://192.168.122.1/current_os/Module-Basesystem/
gpgcheck=0
gpgkey=http://192.168.122.1/current_os/Module-Basesystem/repodata/repomd.xml.key
enabled=1

[server-applications]
name=server-applications
type=rpm-md
baseurl=http://192.168.122.1/current_os/Module-Server-Applications/
gpgcheck=0
gpgkey=http://192.168.122.1/current_os/Module-Server-Applications/repodata/repomd.xml.key
enabled=1

[product-sles]
name=product-sles
type=rpm-md
baseurl=http://192.168.122.1/current_os/Product-SLES/
gpgcheck=0
gpgkey=http://192.168.122.1/current_os/Product-SLES/repodata/repomd.xml.key
enabled=1
```

current_ses.repo file:

```
# cat /srv/www/htdocs/current_ses.repo 
[SES]
name=SES
type=rpm-md
baseurl=http://192.168.122.1/current_ses/
gpgcheck=0
gpgkey=http://192.168.122.1/current_ses/repodata/repomd.xml.key
enabled=1
```

####  Enable and start services:

```bash
systemctl enable docker libvirtd nfs-server apache2
systemctl start docker libvirtd nfs-server apache2
```

#### Firewall

Firewall should be disabled by default 

```bash
systemctl disable SuSEfirewall2
systemctl stop SuSEfirewall2
```

In some cases default Libvirt iptables rules are not desired. We are going to remove all REJECT rules.

```
iptables-save > /etc/iptables_orig.conf
cp /etc/iptables_orig.conf /etc/iptables.conf
sed -i '/REJECT/d' /etc/iptables.conf
iptables-resore /etc/iptables.conf
```

We have to restore these rules after every system or libvirt service reboot.

#### SSH keys

Vagrant is looking for *storage-automation* public and private keys in `/root/.ssh/` path. If they are placed there we will be able to login without password to our deployed SES cluster. Thanks to *vagrant-hostsupdater* plugin we can use hostnames we defined in YAML file.

#### Setting up Docker registry cache

Pull from registry.suse.com a specific version of the container image called "registry":

```
docker pull registry.suse.com/sles12/registry:2.6.2
```

Create a directory for storing the imagesour container cache will know about:

```
mkdir -p /docker/perstorage/registry/data
```

Create config.yaml file one directory above:

```
# cat /docker/perstorage/registry/config.yml


version: 0.1 
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  maintenance:
    readonly:
      enabled: true
http:
  addr: 0.0.0.0:5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
threshold: 3
proxy:
  remoteurl: https://registry.suse.de
```

Start container cache:

```
docker run -d --restart=always --name locreg -p 5000:5000 \
        -v /docker/perstorage/registry/data:/var/lib/registry \
        -v /docker/perstorage/registry/config.yml:/etc/docker/registry/config.yml \
        -v /usr/share/pki/trust/anchors/SUSE_Trust_Root.crt.pem:/var/lib/ca-certificates/ca-bundle.pem \
        registry.suse.com/sles12/registry:2.6.2 serve /etc/docker/registry/config.yml
```

Make sure that container is installed:

```
docker ps -a
```

Take a look into the container cache:

```
curl -s http://localhost:5000/v2/_catalog | jq
```

Pull container image from https://registry.suse.de

```
docker pull localhost:5000/suse/sle-15-sp2/update/products/ses7/milestones/containers/ses/7/ceph/ceph:latest
```

New image should be available:

```
docker image list
curl -s http://localhost:5000/v2/_catalog | jq
```

#### Change Vagrant home directory location

Vagrant is using your user home directory to store its data. In some cases it's not what we want. As it may eat all of your disk space.

Therefore we're going to move it under */qemu*

```
mkdir /qemu/vagrant
rsync -avP $HOME/.vagrant.d /qemu/vagrant
```

Set up new Vagrant home in your *~/.bashrc*

```
VAGRANT_HOME=/qemu/vagrant/.vagrant.d
```

Apply changes

```
source ~/.bashrc
```

#### NFS Server settings

Enable **udp** port in */etc/nfs.conf*

```
udp=y
```

Restart *nfs-server* service

```
systemctl restart nfs-server
```

#### Additional server configuration for testing SES cluster with mixed architecture

We need libvirt to be able to emulate aarch64 architecture.

Following steps needs to be done additionaly:

install these packages:

```
zypper in ovmf qemu-arm
```

in the folder [libvirt_files_for_aarch64_emulation](https://gitlab.suse.de/denispolom/vagrant_ses/-/tree/master/mixed_arch/libvirt_files_for_aarch64_emulation) are files that we have to copy in to the following locations:

```bash
/usr/share/qemu/aavmf-aarch64-code.bin
/usr/share/qemu/aavmf-aarch64-vars.bin
/usr/share/qemu/firmware/60-aavmf-aarch64.json
```

We need to enable nvram support in QEMU

Edit file `/etc/libvirt/qemu.conf` and uncomment or add these lines

```
nvram = [
   "/usr/share/qemu/ovmf-x86_64-ms-4m-code.bin:/usr/share/qemu/ovmf-x86_64-ms-4m-vars.bin",
   "/usr/share/qemu/ovmf-x86_64-ms-code.bin:/usr/share/qemu/ovmf-x86_64-ms-vars.bin",
   "/usr/share/qemu/aavmf-aarch64-code.bin:/usr/share/qemu/aavmf-aarch64-vars.bin"
]
```

Create directories for aarch64 repositories:

```
mkdir /srv/www/htdocs/current_aarch64_os
mkdir /srv/www/htdocs/current_aarch64_ses
```

Download and mount desired OS and SES versions:

```
wget -P /qemu/iso <OS ISO url>
mount <path to OS ISO> /srv/www/htdocs/current_aarch64_os
wget -P /qemu/iso <SES ISO url>
mount <path to SES ISO> /srv/www/htdocs/current_aarch64_ses
```

Create repo files for aarch64 under /srv/www/htdocs:

file `current_aarch64_os.repo`

```
[basesystem]
name=basesystem
type=rpm-md
baseurl=http://192.168.122.1/current_aarch64_os/Module-Basesystem/
gpgcheck=0
gpgkey=http://192.168.122.1/current_aarch64_os/Module-Basesystem/repodata/repomd.xml.key
enabled=1

[server-applications]
name=server-applications
type=rpm-md
baseurl=http://192.168.122.1/current_aarch64_os/Module-Server-Applications/
gpgcheck=0
gpgkey=http://192.168.122.1/current_aarch64_os/Module-Server-Applications/repodata/repomd.xml.key
enabled=1

[product-sles]
name=product-sles
type=rpm-md
baseurl=http://192.168.122.1/current_aarch64_os/Product-SLES/
gpgcheck=0
gpgkey=http://192.168.122.1/current_aarch64_os/Product-SLES/repodata/repomd.xml.key
enabled=1
```

file `current_aarch64_ses.repo`

```
[SES]
name=SES
type=rpm-md
baseurl=http://192.168.122.1/current_aarch64_ses/
gpgcheck=0
gpgkey=http://192.168.122.1/current_aarch64_ses/repodata/repomd.xml.key
enabled=1
```

### Preparing for Build Validation tests

#### Creating Vagrant Box

In this example we are going to use SLE-15-SP2-Snapshot15 and SES7-M10.

##### Download and mount ISOs

We are not using prepared vagrant images but creating our own.


Download OS image:

```
mkdir /qemu/iso
wget http://download.suse.de/install/SLE-15-SP2-Full-Snapshot15/SLE-15-SP2-Full-x86_64-Snapshot15-Media1.iso -P /qemu/iso
```

Mount ISO under */srv/www/htdocs/current_os* directory

```
mount /qemu/iso/SLE-15-SP2-Full-x86_64-Snapshot15-Media1.iso /srv/www/htdocs/current_os
```

Download SES image:

```
wget http://download.suse.de/install/SUSE-Enterprise-Storage-7-Milestone10/SUSE-Enterprise-Storage-7-DVD-x86_64-Milestone10-Media1.iso -P /qemu/iso
```

Mount ISO under */srv/www/htdocs/current_ses* directory

```
mount /qemu/iso/SUSE-Enterprise-Storage-7-DVD-x86_64-Milestone10-Media1.iso /srv/www/htdocs/current_ses
```

Additionally for mixed architecture tests:

Mount ISO under */srv/www/htdocs/current_aarch64_os* directory

```
mount /qemu/iso/SLE-15-SP2-Full-aarch64-Snapshot15-Media1.iso /srv/www/htdocs/current_aarch64_os
```

Mount ISO under */srv/www/htdocs/current_aarch64_ses* directory

```
mount /qemu/iso/SUSE-Enterprise-Storage-7-DVD-aarch64-Milestone10-Media1.iso /srv/www/htdocs/current_ses
```

##### QEMU VM installation for Vagrant box with autoyast file

###### x86_64

Insert [autoyast file](https://gitlab.suse.de/denispolom/vagrant_ses/-/blob/master/autoyast/autoyast_intel.xml) into Apache DocumetnRoot directory

```
cp autoyast_intel.xml /srv/www/htdocs
```

Make sure OS image is mounted under */srv/www/htdocs/current_os*

```
mount | grep current_os
```

Install QEMU VM with virt-install:

```
virt-install --name vgrbox --memory 2048 --vcpus 1 --hvm \
--disk bus=virtio,path=/qemu/pools/default/vgrbox.qcow2,cache=none,format=qcow2,size=10  \
--network bridge=virbr0,model=virtio --connect qemu:///system  --os-type linux \
--os-variant sle15sp2 --virt-type kvm --noautoconsole --accelerate \
--location http://192.168.122.1/current_os \
--extra-args="console=tty0 console=ttyS0,115200n8 autoyast=http://192.168.122.1/autoyast_intel.xml"
```

Watch installation:

```
virsh console vgrbox
```

After VM reboots you need to start it manually:

```
virsh start vgrbox
```

Watch autoyast 2nd stage installation

```
virsh console vgrbox
```

After VM reboots second time **DO NOT START IT AGAIN**

Continue with [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)

###### AARCH64 and Mixed

Insert [autoyast file](https://gitlab.suse.de/denispolom/vagrant_ses/-/blob/master/autoyast/autoyast_aarch64.xml) into Apache DocumetnRoot directory

```
cp autoyast_intel.xml /srv/www/htdocs
```

Make sure OS image is mounted under */srv/www/htdocs/current_os*

```
mount | grep current_os
```

Install QEMU VM with virt-install:

```
virt-install --name vgrbox --memory 2048 --vcpus 1 --hvm \
--disk bus=virtio,path=/qemu/pools/default/vgrbox.qcow2,cache=none,format=qcow2,size=10  \
--network bridge=virbr0,model=virtio --connect qemu:///system  --os-type linux \
--os-variant sle15sp2 --arch aarch64 --noautoconsole --accelerate \
--location http://192.168.122.1/current_os \
--extra-args="console=ttyAMA0,115200n8 autoyast=http://192.168.122.1/autoyast_aarch64.xml"
```

Watch installation:

```
virsh console vgrbox
```

After VM reboots you need to start it manually:

```
virsh start vgrbox
```

Watch autoyast 2nd stage installation

```
virsh console vgrbox
```

After VM reboots second time **DO NOT START IT AGAIN**

Continue with [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)



##### QEMU VM installation for Vagrant box manually

###### x86_64

Make sure OS image is mounted under */srv/www/htdocs/current_os*

```
mount | grep current_os
```

Install QEMU VM with virt-install:

```
virt-install --name vgrbox --memory 2048 --vcpus 1 --hvm \
--disk bus=virtio,path=/qemu/pools/default/vgrbox.qcow2,cache=none,format=qcow2,size=10 \
--network bridge=virbr0,model=virtio --connect qemu:///system  --os-type linux \
--os-variant sle15sp2 --virt-type kvm --noautoconsole --accelerate \
--location http://192.168.122.1/current_os --extra-args="console=tty0 console=ttyS0,115200n8"
```

Watch installation:

```
virsh console vgrbox
```

After VM reboots you need to start it manually:

```
virsh start vgrbox
```

Login into the VM using console

```
virsh console vgrbox
```

Create bash file */tmp/vgrsetup.sh*

```
set -ex
useradd -m vagrant
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 600 /etc/sudoers.d/vagrant
mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
wget --no-check-certificate \
https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub \
-O /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh
truncate -s 0 /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/wicked/* ~/.bash_history
poweroff
```

Run

```
while $(zypper lr 1 >/dev/null 2>&1); do zypper rr 1 >/dev/null 2>&1; done
```

Run our bash file

```
bash /tmp/vgrsetup.sh
```

After VM shutdown **DO NOT START IT AGAIN**

Continue with [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)

###### AARCH64 and Mixed

Make sure OS image is mounted under */srv/www/htdocs/current_os*

```
mount | grep current_os
```

Install QEMU VM with virt-install:

```
virt-install --name vgrbox --memory 2048 --vcpus 1 --hvm \
--disk bus=virtio,path=/qemu/pools/default/vgrbox.qcow2,cache=none,format=qcow2,size=10 \
--network bridge=virbr0,model=virtio --connect qemu:///system  --os-type linux \
--os-variant sle15sp2 --arch aarch64 --noautoconsole --accelerate \
--location http://192.168.122.1/current_os --extra-args="console=ttyAMA0,115200n8"
```

Watch installation:

```
virsh console vgrbox
```

After VM reboots you need to start it manually:

```
virsh start vgrbox
```

Login into the VM using console

```
virsh console vgrbox
```

Create bash file */tmp/vgrsetup.sh*

```
set -ex
useradd -m vagrant
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 600 /etc/sudoers.d/vagrant
mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
wget --no-check-certificate \
https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub \
-O /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh
truncate -s 0 /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/wicked/* ~/.bash_history
poweroff
```

Create script `/boot/efi/startup.nsh` to start UEFI boot loader with path to your boot loader, mostly:

```
\EFI\sles\grubaa64.efi
```

Set up permissions:

```
chmod 644 /boot/efi/startup.nsh
```

Run

```
while $(zypper lr 1 >/dev/null 2>&1); do zypper rr 1 >/dev/null 2>&1; done
```

Run our bash file

```
bash /tmp/vgrsetup.sh
```

After VM shutdown **DO NOT START IT AGAIN**

Continue with [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)

##### QEMU VM installation for Vagrant box Clients

Make sure OS image is mounted under */srv/www/htdocs/client*

```
mount | grep client
```

Install QEMU VM with virt-install:

```
virt-install --name vgrbox --memory 2048 --vcpus 1 --hvm \
--disk bus=virtio,path=/qemu/pools/default/vgrbox.qcow2,cache=none,format=qcow2,size=10  \
--network bridge=virbr0,model=virtio --connect qemu:///system  --os-type linux \
--os-variant sle15sp2 --virt-type kvm --noautoconsole --accelerate \
--location http://192.168.122.1/client --extra-args="console=tty0 console=ttyS0,115200n8"
```

Watch installation:

```
virsh console vgrbox
```

After VM reboots you need to start it manually:

```
virsh start vgrbox
```

Login into the VM using console

```
virsh console vgrbox
```

Some distributions like Fedora or RHEL or Ubuntu are not naming NIC with *eth* 

We have to change it:

Edit `/etc/default/grub` file 

```
GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity"
GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"
```

Run

```
grub-mkconfig -o /boot/grub/grub.cfg
```

For Ubuntu 18.04 and higher change the file /etc/netplan/50-cloud-init.yaml to contain following:

```
network:
    ethernets:
        eth0:
            addresses: []
            dhcp4: true
            optional: true
    version: 2
```

Create bash file */tmp/vgrsetup.sh*

```
set -ex
useradd -m vagrant
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 600 /etc/sudoers.d/vagrant
mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
wget --no-check-certificate \
https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub \
-O /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh
truncate -s 0 /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/wicked/* ~/.bash_history
poweroff
```

Run our bash file

```
bash /tmp/vgrsetup.sh
```

After VM shutdown **DO NOT START IT AGAIN**

Continue with [Put image into the Vagrant boxes](#put-image-into-the-vagrant-boxes)

##### Put image into the Vagrant boxes

Go into the Vagrant Home directory and create directory structure

```
mkdir -p /qemu/vagrant/.vagrant.d/boxes/sle15sp2snap15/0/libvirt
```

Create metadata file:

``` 
# cat /qemu/vagrant/.vagrant.d/boxes/sle15sp2snap15/0/libvirt/metadata.json

{
  "provider"     : "libvirt",
  "format"       : "qcow2",
  "virtual_size" : 10
}
```

Create Vagrantfile:

```
# cat /qemu/vagrant/.vagrant.d/boxes/sle15sp2snap15/0/libvirt/Vagrantfile

Vagrant.configure("2") do |config|
         config.vm.provider :libvirt do |libvirt|
         libvirt.driver = "kvm"
         libvirt.host = 'localhost'
         libvirt.uri = 'qemu:///system'
         end
config.vm.define "new" do |custombox|
         custombox.vm.box = "custombox"       
         custombox.vm.provider :libvirt do |test|
         test.memory = 1024
         test.cpus = 1
         end
         end
end
```

Move our VM into this directory

```
mv /qemu/pools/default/vgrbox.qcow2 /qemu/vagrant/.vagrant.d/boxes/sle15sp2snap15/0/libvirt/box.img
```

Verify:

```
# vagrant box list
sle15sp2snap15
```

Undefine VM from libvirt DB

```
virsh undefine vgrbox
```

Create symbolic links (this is much faster and space saving if compared what Vagrant is doing)

```
ln -s /qemu/vagrant/.vagrant.d/boxes/sle15sp2snap15/0/libvirt/box.img \
/qemu/pools/default/sle15sp2snap15_vagrant_box_image_0.img
```

Restart libvirt daemon

```
systemctl restart libvirtd
```

### Vagrant with OpenStack

There is a server *ecp-registry.openstack.local* (IP 10.86.1.251, login with storage-automation key) on OpenStack that runs Apache and Docker to provide repositories and Docker container cache with same setup as was described in 

- [Enable symbolic links in Apache DocumentRoot](#enable-symbolic-links-in-apache-documentroot)

- [Create repo files and repo directories](#create-repo-files-and-repo-directories)

- [Setting up Docker registry cache](#setting-up-docker-registry-cache)

#### Preparing for Build Validation test with OpenStack

We need to patch [cinder files](https://gitlab.suse.de/denispolom/vagrant_ses/-/tree/master/openstack%2Fcinder) to work with ECP.

Go to your vagrant home directory and run

```
cd .vagrant.d
find . -name cinder.rb
```

replace the file with [cinder.rb](https://gitlab.suse.de/denispolom/vagrant_ses/-/tree/master/openstack%2Fcinder) 

same for [cinder_spec.rb](https://gitlab.suse.de/denispolom/vagrant_ses/-/tree/master/openstack%2Fcinder)

```
find . -name cinder_spec.rb
```

##### Creating OpenStack image

Download and source RC file from OpenStack.

Find existing JeOS image of required OS and create instance of it.

Download JeOS qcow2 file for example with name sle15sp2snap15-jeos.qcow2 to your local server.

Create image:

```
openstack image create --private --disk-format qcow2 --project-domain ses --file /qemu/pools/default/sle15sp2snap15-jeos.qcow2 sle15sp2snap15
```

We have to change some settings in image

Create instance

```
openstack server create --image sle15sp2snap15 --flavor m1.small --key-name storage-automation --availability-zone nova --network sesci sle15testimage
```

Get free floating IP and assign to instance

```
openstack floating ip list | grep -i none | tail -1
openstack server add floating ip sle15sp2testimage <IP>
```

Log in to the server as user **sles** and switch to root with `sudo su -`:

replace `/etc/cloud/cloud.cfg` file with [this file](https://gitlab.suse.de/denispolom/vagrant_ses/-/blob/master/openstack/cloud/cloud.cfg)

In user root home directory remove restrictions from beggining of line in `/root/.ssh/authorized_keys` file that it will looks like normal public key context.

execute commands:

```bash
systemctl restart cloud-init
netconf update -f
SUSEConnect -r <reg number>
zypper in -t pattern yast2_basis base enhanced_base
zypper in kernel-default
```

Create bash file */tmp/vgrsetup.sh*

```
set -ex
useradd -m vagrant
echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
chmod 600 /etc/sudoers.d/vagrant
mkdir -p /home/vagrant/.ssh
chmod 0700 /home/vagrant/.ssh
wget --no-check-certificate \
https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub \
-O /home/vagrant/.ssh/authorized_keys
chmod 0600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh
truncate -s 0 /etc/udev/rules.d/70-persistent-net.rules
rm -f /var/lib/wicked/* ~/.bash_history
poweroff
```

Create new image from instance

```
nova image-create --show --poll sle15sp2snap15 <image name>
```

Try to create instance from new image and watch if it boots properly

Continue on server ecp-registry with steps described in [Download and mount ISOs](#download-and-mount-isos)

### Running Build Validation tests

Clone the *vagrant_ses* project.

Structure is according architecture we are going to deploy SES cluster and run tests on or there is *openstack* directory if we are going to deploy SES cluster on OpenStack.

`./vagrant_ses/scripts` directory contains bash scripts used for testing on SES6 and they are linked into appropriate folder.

For SES7 there is separate *scripts* directory under `./vagrant_ses/<architecture>/SES7/` or `./vagrant_ses/openstack/SES7/`.

#### Build Validation on x86_64, AARCH64 and Mixed

We are going to use SES7 and vagrant box sle15sp2snap15 as an example.

Edit YAML file with vagrant box for deployment:

```yaml
ses_cl_box: 'sle15sp2snap15'
```

##### Running tests with build validation script

If we are going to use `build_validation.sh` script then only these scripts needs to be enabled in YAML:

```yaml
master_sh:
        - hosts_file_correction.sh
        - deploy_ses.sh

monitor_sh:
        - configure_ses.sh
```

All other scripts are handled by *build_validation.sh* script

In most cases nothing more needs to be edited.

Run test:

```
./build_validation.sh SES7_Build_Validation 2>&1 | tee -a logfile.log
```

What is script doing:

  - deploys SES cluster with Vagrant using repositories we did set up in [Download and mount ISOs](#download-and-mount-isos) or if we selected SCC in YAML then it using these repositories for deploying SES and for OS. We also can use these options together if we need to test some additional packages that are not available in SCC.

  - creates snapshot *deployment* of fresh deployed cluster

  - if some script fails then

      - it collects supportconfig logs from whole cluster and copies them to *./logs/* directory

      - creates snapshot of cluster with name of the script that failed

      - reverts to fresh deployed cluster snapshot

  - reverts to fresh deployed cluster snapshot after each script is finished 

We can manage cluster also with virsh tool

```
# virsh list 
 Id   Name             State
--------------------------------
 33   SES7_master      running
 34   SES7_osd-node1   running
 35   SES7_osd-node2   running
 36   SES7_osd-node3   running
 37   SES7_osd-node4   running
 38   SES7_osd-node5   running
 39   SES7_monitor1    running
 40   SES7_monitor2    running
 41   SES7_monitor3    running
```

```
# virsh snapshot-list SES7_master
 Name         Creation Time               State
---------------------------------------------------
 deployment   2020-05-14 13:24:18 +0200   shutoff
```

Our project directory (where Vagrnat files and scripts folder are located) is mounted over NFS to each server under `/vagrant` directory.

##### Running tests just with Vagrant

Edit YAML file as described in [Running tests with build validation script](#running-tests-with-build-validation-script)

and additionally enable scripts you want Vagrnat to run on SES cluster. They will run in order as they are in YAML file. 

Disadvantage is that Build Validation test will fail if some of the scripts will fail and cluster may stay in broken state. You will need to destroy it and run again.

Run tests

```
VAGRANT_VAGRANTFILE=SES7_Build_Validation vagrant up
```

Destroy cluster

```
VAGRANT_VAGRANTFILE=SES7_Build_Validation vagrant destroy -f
```

##### Destroying project on AARCH64 or Mixed 

Vagrant can't destroy libvirt domain as it is using nvram.

Use `destroy_project.sh` 

```
./destroy_project.sh <Vagrantfile>
```

#### Running tests on OpenStack

Go into the folder ./vagrant_ses/openstack/SES7

Download RC file from OpenStack and source it.

```
source ses-openrc.sh
```

Edit YAML file as described in [Running tests just with Vagrant](#running-tests-just-with-vagrant) where *ses_cl_box* is the name of the image.

Run

```
python prepare_openstack_for_vagrant.py -y SES7_Build_validation_OpenStack.yaml -f SES7_Build_validation_OpenStack
```

it will delete servers definded in YAML file from OpenStack if they exists and delete "vgr_volume\*" and creates new ones

run 

```bash
VAGRANT_VAGRANTFILE=SES7_Build_validation_OpenStack vagarant up --provider=openstack
```
