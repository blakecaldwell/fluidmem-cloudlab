#!/bin/bash  

echo "*********************************"
echo "Starting Infiniswap install"
echo "*********************************"

NAME=$(hostname|cut -d'.' -f1)

[[ $HOME ]] || HOME=/root

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
  sudo apt-get -y remove libibnetdisc5
  sudo apt-get remove -y kernel-mft-dkms

  curl -Lo MLNX_OFED_LINUX-3.4-1.0.0.0-ubuntu14.04-x86_64.tgz https://www.dropbox.com/s/op43xec3nx2cxzf/MLNX_OFED_LINUX-3.4-1.0.0.0-ubuntu14.04-x86_64.tgz?dl=1 &> /dev/null
  tar -xf MLNX_OFED_LINUX-3.4-1.0.0.0-ubuntu14.04-x86_64.tgz
  cd MLNX_OFED_LINUX-3.4-1.0.0.0-ubuntu14.04-x86_64/
  sudo ./mlnxofedinstall --add-kernel-support
  sudo rmmod mlx5_fpga_tools
  sudo /etc/init.d/openibd restart
  set +e
}

build_infiniswap() {
  set -e
  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  
  COMMIT=master
  git clone https://github.com/SymbioticLab/Infiniswap.git ${BUILD_DIR}
  cd ${BUILD_DIR}

  sed -i 's/#max_remote_memory=/max_remote_memory=8/' setup/install.sh

  cd setup
  export ip=$(ip a show dev ib0|grep inet|grep -v inet6|awk '{print $2}'|sed 's/\(.*\)\/.*/\1/')
  sudo ./ib_setup.sh $ip

  if [[ "$NAME" == "cp-1" ]]; then
    ./install.sh daemon
  else
    ./install.sh bd

    HOSTS=$(cat /etc/hosts|grep cp-|grep -v cp-1|awk '{print $4}'|sort)
    let i=0 || true
    for each in $HOSTS; do
      (( i += 1 ))
    done

    #cat <<EOF | tee ${BUILD_DIR}/setup/portal.list > /dev/null
#$i
#$(for each in $HOSTS; do echo "$(grep $each /etc/hosts|awk '{print $1}'):9400"; done)
#EOF
    sudo apt-get install -y cgroup-bin cgroup-lite libcgroup1
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

    sudo cgcreate -g memory:/myGroup
    sudo cgset -r memory.limit_in_bytes=1m myGroup
    echo "*:pmbench memory myGroup" | sudo tee /etc/cgrules.conf
    sudo cgrulesengd
  fi
  set +e
}


set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  prepare_infiniswap_ubuntu
  build_infiniswap
  start_infiniswap
fi



# let other installs continue
rm -f /tmp/infiniswap-lock

echo "*********************************"
echo "Finished setting up Infiniswap"
echo "*********************************"
set +e
