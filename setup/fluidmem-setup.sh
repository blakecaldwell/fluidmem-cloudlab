#!/bin/bash  

die() { echo "$@" 1>&2 ; exit 1; }

if [ -e /opt/.fluidmem-installed ]; then
  echo "Already installed fluidmem"
  exit 0
fi

echo "*********************************"
echo "Starting FluidMem install"
echo "*********************************"

if [[ $EUID -eq 0 ]]; then
  HOME=/root
fi

[[ $HOME ]] || {
  HOME=/opt
  sudo chmod o+rwx /opt
  sudo chown $USER /opt
}

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
  if [ -d $HOME/RAMCloud ]; then
    RAMCLOUD_BASE=$HOME/RAMCloud
  elif [ -d /opt/RAMCloud ]; then
    RAMCLOUD_BASE=/opt/RAMCloud
  else
    die "Could not find RAMCloud source sirectory in $HOME or /opt"
  fi
  export CPPFLAGS="-I${RAMCLOUD_BASE}/src -I/usr/include/ramcloud"
  export LDFLAGS="-L/usr/lib/ramcloud"
  ./autogen.sh
  ./configure --enable-ramcloud \
      --disable-trace \
      --disable-debug \
      --disable-lock_debug \
      --enable-pagecache \
      --enable-threadedwrite \
      --enable-affinity \
      --enable-asynread \
      --disable-timing \
      --prefix=$(pwd)/build
  make -j10 install
  sudo mkdir /var/run/fluidmem || true
  sudo chown $USER: /var/run/fluidmem/
  # just install libuserfault_client to system paths
  sudo cp build/include/userfault-client.h /usr/local/include/
  sudo cp -d build/lib/libuserfault_client.* /usr/local/lib/
  sudo ldconfig  # update from library in /usr/local/lib
  export PATH=$PATH:$(pwd)/build/bin
  echo "export PATH=\$PATH:$(pwd)/build/bin" >> ~/.bashrc
  set +e
} 

function start_fluidmem {
  CACHE_SIZE=$((1024 * 1024 * 1024 / 4096))
  ip=$(ip a show dev ib0|grep inet|grep -v inet6|awk '{print $2}'|sed 's/\(.*\)\/.*/\1/')
  ZOOKEEPER="$ip:2181"
  LOCATOR="zk:$ZOOKEEPER"
  echo "**********************************************************************************"
  echo "To start FluidMem, run the following comand:"
  echo "$(pwd)/build/bin/monitor $LOCATOR --zookeeper=$ZOOKEEPER --cache_size=${CACHE_SIZE} >> ${BUILD_DIR}/monitor.log 2>&1"
  echo "**********************************************************************************"
}

build_fluidmem
if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error building FluidMem"
  echo "**********************************************************************************"
  exit 2
fi

sudo touch /opt/.fluidmem-installed

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
