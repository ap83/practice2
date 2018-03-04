#!/bin/bash

# Take one argument from the commandline: VM name

if ! [ $# -eq 1 ]; then
    echo "Usage: $0 <node-name>"
    exit 1
fi

# Check if domain already exists
virsh dominfo $1 > /dev/null 2>&1
if [ "$?" -eq 0 ]; then
    echo -n "[WARNING] $1 already exists.  "
    read -p "Do you want to overwrite $1 (y/[N])? " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        virsh destroy $1 > /dev/null
        virsh undefine $1 > /dev/null
    else
        echo -e "\nNot overwriting $1. Exiting..."
        exit 1
    fi
fi

# Directory to store images
DIR=~/cloudinit/images

# Location of cloud image
IMAGE=~/cloudinit/ubuntu-16.04-server-cloudimg-amd64-disk1.img
#IMAGE=~/cloudinit/ubuntu-14.04-server-cloudimg-amd64-disk1.img

# Amount of RAM in MB
MEM=1024

# Number of virtual CPUs
CPUS=1

# Cloud init files
USER_DATA=$DIR/$1/user-data
META_DATA=$DIR/$1/meta-data
NETWORK_DATA=$DIR/$1/network-config
CI_ISO=$DIR/$1/$1-cidata.iso
IP="192.168.122.41"


# Bridge for VMs (default on Fedora is virbr0)
BRIDGE=virbr0

# Start clean
rm -rf $DIR/$1
mkdir -p $DIR/$1

pushd $DIR/$1 > /dev/null

    # Create log file
    touch $1.log

    echo "$(date -R) Destroying the $1 domain (if it exists)..."

    # Remove domain with the same name
    virsh destroy $1 >> $1.log 2>&1
    virsh undefine $1 >> $1.log 2>&1

    cat > $USER_DATA << _EOF_
    #cloud-config

    preserve_hostname: False
    hostname: $1

    users:
      - name: apashchenko
        gecos: Anton Pashchenko
        lock-passwd: false
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys:
          - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCk8Z85IBAz9TphtiUpSROHs6ecqh4kBhD70AdsGi+/gcJib/d0VHBS2kqj5ujcazq/mGoVsi/6M96eRgcj7hplHV0o5DOyld3xF1BMF1YHyvWMMIlWliU+kSmfoOADQtB+5zRb6AWYJmKhWPMWwqpOSJMxNBLXEjol626FXdVqT5KLuAWM8nuediwbYQaAehtLEtYl1EcEU3AbMmFC8aKa3gzxioyuDH6puxTeJFQ9UQ6XPd4dFxQ1jsv/QJdZ0a4xgBx6bE0+AKdlPREGe4ORhPKpfJXodNRBZy61DsTvhTZPaP2BpQH/nsEIoJp7FwHUmbV0cIFYVZdC9Bp9AAbH apashchenko@kbp1-lhp-f76354

    packages:
      - python-minimal

_EOF_

packages:
  - python-minimal

    cat > $NETWORK_DATA << _EOF_
    version: 1
    config:
      - type: physical
        name: ens2
        subnets:
          - type: static
            address: $IP
            netmask: 255.255.255.0
            gateway: 192.168.122.1
      - type: nameserver
        address:
          - 8.8.8.8
          - 8.8.4.4


_EOF_

    echo "instance-id: $1; local-hostname: $1" > $META_DATA

#    echo "Meta data: $(cat $META_DATA)"
#    echo "User data: $(cat $USER_DATA)"
#    echo "Network data: $(cat $NETWORK_DATA)"

    # Create CD-ROM ISO with cloud-init config
    echo "$(date -R) Generating ISO for cloud-init..."
    genisoimage -output $CI_ISO -volid cidata -joliet -rock $USER_DATA $META_DATA $NETWORK_DATA &>> $DIR/$1/$1.log

    echo "$(date -R) Installing the domain and adjusting the configuration..."
    echo "[INFO] Installing with the following parameters:"
    echo "virt-install --import --name $1 --ram $MEM --vcpus $CPUS --disk=$DIR/$1/$1.qcow2,format=qcow2,bus=virtio \
    --disk=$CI_ISO,device=cdrom --network bridge=virbr0,model=virtio \
    --os-type=linux"

    qemu-img convert -O qcow2 $IMAGE $DIR/$1/$1.qcow2

    virt-install --name $1 --ram $MEM --disk=$DIR/$1/$1.qcow2,format=qcow2,bus=virtio --vcpus 1 \
    --network bridge=virbr0,model=virtio --graphics=none --os-type=linux --import \
    --disk=$CI_ISO,device=cdrom


  #  MAC=$(virsh dumpxml $1 | awk -F\' '/mac address/ {print $2}')
#    while true
#    do
#        IP=$(grep -B1 $MAC /var/lib/libvirt/dnsmasq/$BRIDGE.status | head -n 1 | awk '{print $2}' | sed -e s/\"//g -e s/,//)
#        if [ "$IP" = "" ]
#        then
#            sleep 1
  #      else
#            break
#        fi
#    done

    # Eject cdrom
#    echo "$(date -R) Cleaning up cloud-init..."
#    virsh change-media $1 hda --eject --config >> $1.log

    # Remove the unnecessary cloud init files
  #  rm $USER_DATA $CI_ISO

    echo "$(date -R) DONE. SSH to $1 using $IP with username 'apashchenko'."

popd > /dev/null
