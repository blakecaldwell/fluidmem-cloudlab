#!/bin/bash  

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

install_docker_ubuntu() {
  # get prerequisites for adding the docker repository and verifying with the GPG key
  sudo apt-get update
  sudo apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  sudo apt-key fingerprint 0EBFCD88
  # add the docker repository to apt sources list
  bash -c 'sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"'
  sudo apt-get update
  # install docker packages
  sudo apt-get -y install docker-ce docker-ce-cli containerd.io
}

install_docker_centos () {
  sudo yum install -y \
    docker && \
    yum clean all

}

set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  install_docker_ubuntu
elif [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  install_docker_centos
fi

# let other installs continue
rm -f /tmp/docker-lock


echo "*********************************"
echo "Finished setting up Docker"
echo "*********************************"
set +e
