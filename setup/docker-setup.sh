#!/bin/bash  

echo "*********************************"
echo "Starting Docker/CRIU install"
echo "*********************************"

[[ $HOME ]] || HOME=/root

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/criu
  sudo mkdir -p $BUILD_DIR
  sudo chown $USER:$(id -g) $BUILD_DIR
  ln -s $BUILD_DIR $HOME/criu
else
  BUILD_DIR=$HOME/criu	
  mkdir $BUILD_DIR
fi

prepare_ubuntu() {

  set -e
  # get prerequisites for adding the docker repository and verifying with the GPG key
  sudo apt-get update
  sudo apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common libprotobuf-dev libprotobuf-c0-dev protobuf-c-compiler protobuf-compiler python-protobuf
  # CRIU
  UBUNTU_RELEASE=$(cat /etc/lsb-release |grep DISTRIB_RELEASE|cut -d'=' -f2)
  if [ -z $UBUNTU_RELEASE ]; then
    die "Error: could not detect Ubuntu release from /etc/lsb-release"
  fi
  if [[ "$UBUNTU_RELEASE" =~ "16.04" ]]; then
    sudo apt-get install -y  --no-install-recommends python3-future python-ipaddress
  fi
  sudo apt-get install -y  --no-install-recommends pkg-config libbsd-dev libcap-dev libnl-3-dev libnet-dev libaio-dev asciidoc xmlto

}

install_ubuntu() {
  set -e

  # docker
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo apt-key fingerprint 0EBFCD88
  # add the docker repository to apt sources list
  bash -c 'sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"'
  sudo apt-get update
  # install docker packages
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io

  # CRIU

  git clone https://github.com/checkpoint-restore/criu.git $BUILD_DIR
  cd $BUILD_DIR
  git checkout master
  make
  sudo make install

  echo -e '{\n    "experimental": true\n}' | sudo tee -a /etc/docker/daemon.json

  set +e
}

install_docker_centos () {
  set -e
  sudo yum install -y \
    docker && \
    yum clean all
  set +e
}

set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  prepare_ubuntu
  install_ubuntu
elif [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  install_docker_centos
fi

if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error installing Docker"
  echo "**********************************************************************************"
  exit 2
fi

# let other installs continue
rm -f /tmp/docker-lock


echo "*********************************"
echo "Finished setting up Docker and CRIU"
echo "*********************************"
set +e
