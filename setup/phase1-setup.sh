#!/bin/bash

###############
# phase1-setup.sh
#
# Blake Caldwell <caldweba@colorado.edu>
# December 11th, 2015
#
# Purpose: automatically run setup script for cloudlab systems
#            1. passwordless ssh between nodes
#            2. Infiniband packages and config for RDMA (requires reboot)
###############

set -x

if [ -e "/opt/.phase1_setup_complete" ]; then
  echo "Phase 1 setup has already completed"
  exit 0
fi

chmod +x /opt/setup/*.sh

# Any SSDs to use?
SSD=$(lsblk -o NAME,MODEL|grep SSD | awk 'NR==1{print $1}')

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  mkfs.ext4 /dev/$SSD && \
    mkdir /ssd && \
    mount /dev/$SSD /ssd && \
    mkdir /ssd/apt-cache && \
    echo "dir::cache::archives /ssd/apt-cache" > /etc/apt/apt.conf.d/10-ssd-cache
  export SSD
  mkdir /mnt/second_drive
  ln -s /ssd /mnt/second_drive
else
  if [ -e /dev/sdd ]; then
    DEVICE=/dev/sdd
  elif [ -e /dev/sdc ]; then
    DEVICE=/dev/sdc
  elif [ -e /dev/sdb ]; then
    DEVICE=/dev/sdb
  fi
  mkdir /mnt/second_drive
  mkfs.ext4 "$DEVICE" && \
    mount "$DEVICE" /mnt/second_drive
  unset SSD 
fi

# install packages for each distro type
if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  yum -y update
  yum -y install pciutils
  yum groupinstall -y "Infiniband Support"
  yum install -y infiniband-diags perftest libibverbs-utils librdmacm-utils libipathverbs libmlx4
  yum install -y librdmacm-devel libibverbs-devel numactl numactl-devel libaio-devel libevent-devel

elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then

  locale-gen en_US
  export DEBIAN_FRONTEND=noninteractive

  # for building
  apt-get update
  apt-get install -y libtool autoconf automake build-essential vim

  # for rdma
  apt-get install -y ibverbs-utils rdmacm-utils infiniband-diags perftest libipathverbs1 libmlx4-1 libmthca1 
  apt-get install -y librdmacm-dev libibverbs-dev numactl libnuma-dev libaio-dev libevent-dev libmlx4-dev
  apt-get install -y pdsh

  for module in ib_umad ib_uverbs rdma_cm rdma_ucm ib_qib mlx4_core mlx4_en mlx4_ib; do
    echo $module | tee -a /etc/modules
  done

  # get last octet of IP address
  SUFFIX=$(ip a| grep "eth\|enp\|eno"|grep inet|awk '{print $2}'|cut -d '.' -f4|cut -d '/' -f1)

  cat <<EOF | tee -a /etc/network/interfaces > /dev/null
auto ib0
iface ib0 inet static
    address 10.0.1.${SUFFIX}/24
    pre-up modprobe mlx4_ib
    pre-up modprobe ib_umad
    pre-up modprobe ib_uverbs
    pre-up modprobe ib_ipoib
EOF
fi

# set the amount of locked memory. will require a reboot
cat <<EOF  | tee /etc/security/limits.d/90-rmda.conf > /dev/null
* soft memlock unlimited
* hard memlock unlimited
EOF

# allow pdsh to use ssh
echo "ssh" | tee /etc/pdsh/rcmd_default

sed -i 's/HostbasedAuthentication no/HostbasedAuthentication yes/' /etc/ssh/sshd_config
cat <<EOF | tee -a /etc/ssh/ssh_config
    HostbasedAuthentication yes
    EnableSSHKeysign yes
EOF

cat <<EOF | tee /etc/ssh/shosts.equiv > /dev/null
$(for each in $HOSTS localhost; do grep $each /etc/hosts|awk '{print $1}'; done)
$(for each in $HOSTS localhost; do echo $each; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $2}'; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $3}'; done)
EOF

# Get the public key for each host in the cluster.
# Nodes must be up first
for each in $HOSTS; do
  while ! ssh-keyscan $each >> /etc/ssh/ssh_known_hosts || \
        ! grep -q $each /etc/ssh/ssh_known_hosts; do
    sleep 1
  done
  echo "Node $each is up"
done

# first name after IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $2}') >> /etc/ssh/ssh_known_hosts
done
# IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $1}') >> /etc/ssh/ssh_known_hosts
done

# for passwordless ssh to take effect
service ssh restart

# done
touch "/opt/.phase1_setup_complete"
