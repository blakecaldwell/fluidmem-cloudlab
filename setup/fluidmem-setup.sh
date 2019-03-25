#!/bin/bash  

echo "*********************************"
echo "Starting FluidMem install"
echo "*********************************"

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

if [[ "$(uname -m)" =~ aarch64.* ]]; then
  echo "**************************************************"
  echo "WARNING: FluidMem will not compile on ARM. Proceeding anyway"
  echo "**************************************************"
fi

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  NOBODY_USR_GRP="nobody:nobody"
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  NOBODY_USR_GRP="nobody:nogroup"
fi

if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/fluidmem
  sudo mkdir -p $BUILD_DIR
  sudo chown $USER:$(id -g) $BUILD_DIR
  ln -s $BUILD_DIR $HOME/fluidmem
else
  BUILD_DIR=$HOME/fluidmem	
  mkdir $BUILD_DIR
fi


build_fluidmem () {
  set -e
  git clone https://github.com/blakecaldwell/fluidmem.git ${BUILD_DIR}
  cd ${BUILD_DIR}
  git checkout master
  export CPPFLAGS=-I${BUILD_DIR}/../RAMCloud/src/
  ./autogen.sh \
    && ./configure --enable-ramcloud \
      --disable-trace \
      --disable-debug \
      --disable-lock_debug \
      --enable-pagecache \
      --enable-pagecache-zeropageopt \
      --enable-threadedprefetch \
      --enable-threadedwrite \
      --enable-affinity \
      --enable-asynread \
      --disable-timing \
      --prefix=$(pwd)/build \
    && make -j10 install
  sudo mkdir /var/run/fluidmem

  set +e
} 

build_fluidmem
if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error building FluidMem"
  echo "**********************************************************************************"
  exit 2
fi

echo "*********************************"
echo "Finished setting up FluidMem"
echo "*********************************"