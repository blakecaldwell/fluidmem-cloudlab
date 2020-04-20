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
  export CPPFLAGS="-I${BUILD_DIR}/../RAMCloud/src -I/usr/include/ramcloud"
  export LDFLAGS="-L/usr/lib/ramcloud"
  ./autogen.sh \
    && ./configure --enable-ramcloud \
      --disable-trace \
      --disable-debug \
      --disable-lock_debug \
      --enable-pagecache \
      --enable-threadedwrite \
      --enable-affinity \
      --enable-asynread \
      --disable-timing \
      --prefix=$(pwd)/build \
    && make -j10 install
  sudo mkdir /var/run/fluidmem
  sudo chown $USER: /var/run/fluidmem/
  echo "export PATH=\$PATH:$(pwd)/build/bin" >> "$HOME/.bashrc"
  export PATH=$PATH:$(pwd)/build/bin
  set +e
} 

function start_fluidmem {
  CACHE_SIZE=$((1024 * 1024 * 1024 / 4096))
  ZOOKEEPER="10.0.0.1:2181"
  LOCATOR="zk:$ZOOKEEPER"
  echo "**********************************************************************************"
  echo "To start FluidMem, run the following comand:"
  echo "monitor $LOCATOR --cache_size=${CACHE_SIZE} >> ${BUILD_DIR}/monitor.log 2>&1"
  echo "**********************************************************************************"
}

build_fluidmem
if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error building FluidMem"
  echo "**********************************************************************************"
  exit 2
fi

start_fluidmem
if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error starting FluidMem"
  echo "**********************************************************************************"
  exit 2
fi

echo "*********************************"
echo "Finished setting up FluidMem"
echo "*********************************"
