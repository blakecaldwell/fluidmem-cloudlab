#!/bin/bash  

if [ -e /opt/.infiniswap-installed ]; then
  echo "Already installed infiniswap"
  exit 0
fi

echo "*********************************"
echo "Starting Infiniswap install"
echo "*********************************"

NAME=$(hostname|cut -d'.' -f1)

if [[ $EUID -eq 0 ]]; then
  HOME=/root
fi

[[ $HOME ]] || {
  HOME=/opt
  sudo chmod o+rwx /opt
  sudo chown $USER /opt
}

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  NOBODY_USR_GRP="nobody:nobody"
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  NOBODY_USR_GRP="nobody:nogroup"
fi

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/Infiniswap
  sudo mkdir -p $BUILD_DIR
  sudo chown $USER:$(id -g) $BUILD_DIR
  ln -s $BUILD_DIR $HOME/Infiniswap
else
  BUILD_DIR=$HOME/Infiniswap
  mkdir $BUILD_DIR
fi

prepare_infiniswap_ubuntu() {
  set -e
  sudo apt-get update
  sudo apt-get remove -y kernel-mft-dkms || true

  if [[ "$UBUNTU_RELEASE" =~ "16.04" ]]; then
    sudo apt-get -y remove libosmcomp3 libibumad3 rdmacm-utils libmthca1 libibmad5 libipathverbs1
    sudo apt-get remove -y ibverbs-utils libibverbs-dev libibverbs1 librdmacm-dev libmlx4-dev libmlx4-1 librdmacm1
    MLNX_OFED="MLNX_OFED_LINUX-4.1-1.0.2.0-ubuntu16.04-x86_64.tgz"
    wget https://www.dropbox.com/s/qupcryelg7yyk42/${MLNX_OFED}.tgz?dl=1 -O ${MLNX_OFED}.tgz
  elif [[ "$UBUNTU_RELEASE" =~ "14.04" ]]; then
    sudo apt-get -y remove libibnetdisc5
    MLNX_OFED="MLNX_OFED_LINUX-3.4-1.0.0.0-ubuntu14.04-x86_64"
    wget https://www.dropbox.com/s/op43xec3nx2cxzf/${MLNX_OFED}.tgz?dl=1 -O ${MLNX_OFED}.tgz
  fi

  tar -xf ${MLNX_OFED}.tgz
  cd ${MLNX_OFED}/

  sudo ./mlnxofedinstall --add-kernel-support --without-dkms
  sudo rmmod mlx5_fpga_tools
  sudo /etc/init.d/openibd restart
  set +e
}

build_infiniswap() {
  set -e
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  
  if [[ "$UBUNTU_RELEASE" =~ "16.04" ]]; then
    git clone --branch without_dkms https://github.com/blakecaldwell/Infiniswap.git ${BUILD_DIR}
  else
    git clone https://github.com/SymbioticLab/Infiniswap.git ${BUILD_DIR}
  fi
  cd ${BUILD_DIR}/setup

  export ip=$(ip a show dev ib0|grep inet|grep -v inet6|awk '{print $2}'|sed 's/\(.*\)\/.*/\1/')
  sudo ./ib_setup.sh $ip

  if [[ "$NAME" == "cp-1" ]]; then
     OPTIONS="--enable-max_remote_memory=32 \
       --enable-remote_memory_evict=8 \
       --enable-evict_hit_limit=1 \
       --enable-remote_memory_expand=16
       --enable-expand_hit_limit=20 \
       --enable-measured_free_mem_weight=0.7"

    cd ${BUILD_DIR}/infiniswap_daemon
    ./autogen.sh
    ./configure $OPTIONS
     make -j2
  else
    OPTIONS="--enable-max_page_num=1 \
      --enable-bio_page_cap=32 \
      --enable-max_remote_memory=32 \
      --enable-stackbd_size=32 \
      --enable-stackbd_name=stackbd \
      --enable-backup_disk=/dev/sdb \
      --enable-num_server_select=1"

   cd ${BUILD_DIR}/infiniswap_bd
    ./autogen.sh
    if [[ "$UBUNTU_RELEASE" =~ "16.04" ]]; then
      ./configure $OPTIONS --enable-lookup_bdev
    else
      ./configure $OPTIONS
    fi
    make -j2
    sudo make install

    HOSTS=$(cat /etc/hosts|grep cp-|grep -v cp-1|awk '{print $4}'|sort)
    let i=0 || true
    for each in $HOSTS; do
      (( i += 1 ))
    done

    #cat <<EOF | tee ${BUILD_DIR}/setup/portal.list > /dev/null
#$i
#$(for each in $HOSTS; do echo "$(grep $each /etc/hosts|awk '{print $1}'):9400"; done)
#EOF
  fi

  set +e
}

start_infiniswap() {
  set -e
  if [[ "$NAME" -eq "cp-1" ]]; then
    cd ${BUILD_DIR}/infiniswap_daemon
    ip=$(ip a show dev ib0|grep inet|grep -v inet6|awk '{print $2}'|sed 's/\(.*\)\/.*/\1/')
    ./infiniswap-daemon $ip 9400 &
  else
    cd ${BUILD_DIR}/setup
    DEV=$(sudo swapon -s|grep -v Filename| awk '{print $1}'| xargs)
    if [[ $? -eq 0 ]] && [[ "$DEV" ]]; then
      sudo swapoff $DEV
    fi
    #sudo ./infiniswap_bd_setup.sh
  fi
  set +e
}


set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  export UBUNTU_RELEASE=$(cat /etc/lsb-release |grep DISTRIB_RELEASE|cut -d'=' -f2)
  if [ -z $UBUNTU_RELEASE ]; then
    die "Error: could not detect Ubuntu release from /etc/lsb-release"
  fi
  prepare_infiniswap_ubuntu
  build_infiniswap
  start_infiniswap
fi


sudo touch /opt/.infiniswap-installed

# let other installs continue
rm -f /tmp/infiniswap-lock

echo "*********************************"
echo "Finished setting up Infiniswap"
echo "*********************************"
set +e
