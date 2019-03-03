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

FLAG="/opt/.usersetup"
SETUPFLAG="/opt/.setup_in_process"
# FLAG will not exist on the *very* fist boot because
# it is created here!
if [ ! -f $SETUPFLAG ]; then
   touch $SETUPFLAG
   touch $FLAG
fi

HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
let i=0
for each in $HOSTS; do
  (( i += 1 ))
done

cat <<EOF | tee /etc/profile.d/firstboot.sh > /dev/null
#!/bin/bash

if [ -f $SETUPFLAG ]; then
  echo "*******************************************"
  echo "RDMA setup in progress. Wait until complete"
  echo "before installing any packages"
  echo "*******************************************"

elif [ -f $FLAG ]; then
  if [ -z "$HOSTS" ]; then
  # single host in cluster
    echo "***********************************************************"
    echo -e "RDMA setup complete"
    echo -e "Run the following command to start second phase of setup.\n\
/usr/local/bin/phase2-setup.sh [ pmem | accelio | grappa | all ]"
    echo "***********************************************************"

  else

    echo "*************************************************************************"
    echo -e "RDMA setup complete"
    echo -e "Your cluster has the following hosts:\n\
$HOSTS\n"
    echo -e "Run the following command to start second phase of setup.\n\
pdsh -w cp-[1-$i] /usr/local/bin/phase2-setup.sh [ pmem | accelio | grappa | all ]"
    echo "*************************************************************************"

  fi
fi
EOF
chmod +x /etc/profile.d/firstboot.sh

cp /tmp/setup/phase2-setup.sh /usr/local/bin/phase2-setup.sh 
cp /tmp/setup/pmem-setup.sh /usr/local/bin/pmem-setup.sh 
cp /tmp/setup/accelio-setup.sh /usr/local/bin/accelio-setup.sh 
cp /tmp/setup/grappa-setup.sh /usr/local/bin/grappa-setup.sh 
chmod +x /usr/local/bin/phase2-setup.sh
chmod +x /usr/local/bin/pmem-setup.sh
chmod +x /usr/local/bin/accelio-setup.sh
chmod +x /usr/local/bin/grappa-setup.sh

# Any SSDs to use?
SSD=$(lsblk -o NAME,MODEL|grep SSD | awk 'NR==1{print $1}')

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  mkfs.ext4 /dev/$SSD && \
    mkdir /ssd && \
    mount /dev/$SSD /ssd && \
    mkdir /ssd/apt-cache && \
    echo "dir::cache::archives /ssd/apt-cache" > /etc/apt/apt.conf.d/10-ssd-cache
  export SSD
else
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

  export DEBIAN_FRONTEND=noninteractive

  # for building
  apt-get install -y libtool autoconf automake build-essential vim

  # for rdma
  apt-get install -y ibverbs-utils rdmacm-utils infiniband-diags perftest libipathverbs1 libmlx4-1
  apt-get install -y librdmacm-dev libibverbs-dev numactl libnuma-dev libaio-dev libevent-dev libmlx4-dev
  apt-get install -y pdsh

  for module in ib_umad ib_uverbs rdma_cm rdma_ucm ib_qib mlx4_core mlx4_en mlx4_ib; do
    echo $module | tee -a /etc/modules
  done
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
rm -f $SETUPFLAG
