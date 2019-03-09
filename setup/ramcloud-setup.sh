#!/bin/bash  

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

if [[ "$(uname -m)" =~ aarch64.* ]]; then
  echo "**************************************************"
  echo "WARNING: RAMCloud will not compile on ARM. Proceeding anyway"
  echo "**************************************************"
fi

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  NOBODY_USR_GRP="nobody:nobody"
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  NOBODY_USR_GRP="nobody:nogroup"
fi

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/RAMCloud
  sudo mkdir -p $BUILD_DIR
  sudo chown $USER:$(id -g) $BUILD_DIR
  ln -s $BUILD_DIR $HOME/RAMCloud
else
  BUILD_DIR=$HOME/RAMCloud	
  mkdir $BUILD_DIR
fi

install_zookeeper_centos() {
  set -e
  cd $HOME
  curl -O http://archive.cloudera.com/cdh5/one-click-install/redhat/6/x86_64/cloudera-cdh-5-0.x86_64.rpm && \
    sudo rpm --import http://archive.cloudera.com/cdh5/redhat/6/x86_64/cdh/RPM-GPG-KEY-cloudera  && \
    sudo yum localinstall -y ./cloudera-cdh-5-0.x86_64.rpm && \
    sudo yum install -y zookeeper-native epel-release && \
    rm -f /cloudera-cdh-5-0.x86_64.rpm
  set +e
}


prepare_ramcloud_ubuntu() {
  set -e
  sudo apt-get update
  sudo apt-get -y install build-essential git-core libcppunit-dev libcppunit-doc doxygen  protobuf-compiler libprotobuf-dev libcrypto++-dev libpcrecpp0v5 libpcre++-dev libssl-dev libpcre3-dev zookeeper zookeeper-bin zookeeperd libzookeeper-mt2 libzookeeper-mt-dev libboost-all-dev openjdk-8-jdk
  sudo service zookeeper start

  set +e
}

build_ramcloud() {

  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"
  
  COMMIT=master
  git clone https://github.com/PlatformLab/RAMCloud ${BUILD_DIR}
  cd ${BUILD_DIR}
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/0002-Remove-references-to-IBV_QPT_RAW_ETH-which-was-remov.patch &> /dev/null

  git am 0002-Remove-references-to-IBV_QPT_RAW_ETH-which-was-remov.patch && \
  git checkout $COMMIT -b b_$COMMIT && \
  git submodule update --init --recursive && \
  ln -s obj.b_$COMMIT obj.master  && \
  sudo make install -j4 INFINIBAND=yes DEBUG=no
}

install_ramcloud_centos() {
  echo "ERROR: not implemented yet."
  exit 1
}

install_ramcloud_ubuntu() {
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/ramcloud-default &> /dev/null
  sudo cp /tmp/setup/ramcloud-default /etc/default/ramcloud

  # get number of replicas
  HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
  let REPLICAS=0
  for each in $HOSTS; do
    (( REPLICAS += 1 ))
  done

  # get our hostname
  IP=$(route -n|awk '$1 == "192.168.0.0" {print $8}'| xargs ip addr show dev|grep inet|grep -v inet6|sed 's/.*inet \(.*\)\/.*/\1/')
  NAME=$(awk "\$1 == \"$IP\" {print \$NF}" /etc/hosts)
  echo "setting up ramcloud config for $NAME"

  COORDINATOR_IP=10.0.0.1
  sudo sed -i -e "s/%%COORDINATOR_IP%%/${COORDINATOR_IP}/" -e "s/%%REPLICAS%%/$REPLICAS/" \
      /etc/default/ramcloud

  if [[ "$NAME" -eq "cp-1" ]]; then
    echo "running both coordinator and server"
    wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/ramcloud-coordinator.service &> /dev/null
    sudo cp /tmp/setup/ramcloud-coordinator.service /lib/systemd/system/ramcloud-coordinator.service
    sudo systemctl enable ramcloud-coordinator
  else
    echo "just running server"
  fi

  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/ramcloud-server.service &> /dev/null
  sudo cp /tmp/setup/ramcloud-server.service /lib/systemd/system/ramcloud-server.service
  sudo systemctl enable ramcloud-server

  cat <<EOF | sudo tee /etc/ld.so.conf.d/ramcloud-x86_64.conf > /dev/null
/usr/lib/ramcloud
EOF
  sudo ldconfig

}

prepare_ramcloud_centos () {
  sudo yum install -y \
    boost-devel \
    boost-system \
    boost-program-options \
    boost-filesystem\
    protobuf-devel \
    protobuf-compiler \
    libibverbs-devel \
    gcc-c++ \
    zlib-devel \
    openssl \
    openssl-devel \
    libibverbs \
    libmlx4 \
    git \
    telnet \
    nc \
    vim \
    java-devel \
    rpm-build && \
    yum clean all

}

set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  prepare_ramcloud_ubuntu
  build_ramcloud
  install_ramcloud_ubuntu
elif [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  install_zookeeper_centos
  prepare_ramcloud_centos
  build_ramcloud
  install_ramcloud_centos
fi



# let other installs continue
rm -f /tmp/ramcloud-lock

echo "*********************************"
echo "Finished setting up RAMCloud"
echo "*********************************"
set +e
