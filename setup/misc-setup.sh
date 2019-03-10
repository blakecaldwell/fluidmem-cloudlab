#!/bin/bash  

echo "*********************************"
echo "Starting misc install"
echo "*********************************"

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  sudo yum  -y install libxml-devel
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  sudo apt-get install -y libxml2-dev libxslt1-dev
fi

cd $HOME
git clone https://bcaldwell@bitbucket.org/jisooy/pmbench.git
cd pmbench
make pmbench

# let other installs continue
rm -f /tmp/misc-lock

echo "*********************************"
echo "Finished setting up Misc"
echo "*********************************"

