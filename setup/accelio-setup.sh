#!/bin/bash  

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

if [[ "$(uname -m)" =~ aarch64.* ]]; then
  echo "**************************************************"
  echo "WARNING: The xio library will not compile on ARM. Proceeding anyway"
  echo "**************************************************"
fi

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  NOBODY_USR_GRP="nobody:nobody"
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  NOBODY_USR_GRP="nobody:nogroup"
fi

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/accelio
  sudo mkdir -p $BUILD_DIR
  sudo chown $USER:$(id -g) $BUILD_DIR
  ln -s $BUILD_DIR $HOME/accelio
else
  BUILD_DIR=$HOME/accelio
  mkdir $BUILD_DIR
fi


build_accelio () {
  git clone https://github.com/accelio/accelio.git ${BUILD_DIR}
  cd ${BUILD_DIR}
  ./autogen.sh \
    && ./configure \
    && make \
    && sudo make install
} 

build_accelio

echo "*********************************"
echo "Finished setting up Accelio (xio)"
echo "*********************************"
