#!/bin/bash

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

# required for munge to be installed

sudo chmod g-w /var/log
# install packages for each distro type
if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  echo "CentOS Grappa install not implemented yet. Exiting..."
  exit 1
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install wget ruby gcc cmake pdsh vim libpmi0-dev munge
  if [[ "$(cat /etc/lsb-release | grep DISTRIB_RELEASE)" =~ 14 ]]; then
    # slurm would not work on 16.04
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install slurm-llnl
  fi
fi

# let other installs continue
rm -f /tmp/grappa-lock

###########################
# Build OpenMPI and grappa
###########################

DATADIR=/proj/$(id -ng)

# Build on SSD if set by phase1
if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BASE_BUILD_DIR=/ssd/build
  sudo mkdir -p $BASE_BUILD_DIR
  sudo chown $USER:$(id -g) $BASE_BUILD_DIR
else
  BASE_BUILD_DIR=$HOME
fi

wait_for_build() {
  cd $DATADIR
  while [ -e build_node ]; do
    sleep $[ ( $RANDOM % 20 )  + 1 ]s
  done
}

build_openmpi() {
  INSTALL_DIR=$DATADIR/build/openmpi
  if [ ! -e $INSTALL_DIR ]; then
    if [ ! -e $DATADIR/build ]; then
      mkdir -p $DATADIR/build
      chmod 1775 $DATADIR/build
    fi
    mkdir $INSTALL_DIR

    cd ${BASE_BUILD_DIR}
    wget https://www.open-mpi.org/software/ompi/v1.10/downloads/openmpi-1.10.1.tar.bz2 &> /dev/null
    tar -xf openmpi-1.10.1.tar.bz2
    cd openmpi-1.10.1
    export CFLAGS=-I/usr/include/slurm
    if [[ "$(uname -m)" =~ aarch64.* ]]; then
      LIBDIR=/usr/lib/aarch64-linux-gnu
    else
      LIBDIR=/usr/lib
    fi
    ./configure --with-devel-headers --prefix=$INSTALL_DIR --with-pmi=/usr/include/slurm --with-pmi-libdir=$LIBDIR --with-slurm
    make all -j20
    make install
    sudo find $INSTALL_DIR -type f -exec chmod g+rw {} \;
    sudo find $INSTALL_DIR -type d -exec chmod g+rwx {} \;
  fi
}

build_grappa() {
  # run on all nodes

  export LD_LIBRARY_PATH=$DATADIR/build/openmpi/lib
  export PATH=$PATH:$DATADIR/build/openmpi/bin

  git clone https://github.com/uwsampa/grappa.git ${BASE_BUILD_DIR}/grappa
  cd ${BASE_BUILD_DIR}/grappa

  if [ ! -e $DATADIR/build ]; then
    mkdir -p $DATADIR/build
    chmod 1775 $DATADIR/build
  fi
  INSTALL_DIR=$DATADIR/build/grappa
  ./configure --cc=$(which gcc) --prefix=$INSTALL_DIR
  cd build/Make+Release/
  make -j20
  cd applications/demos
  make demo-hello_world

  if [ ! -e $HOME/grappa ]; then
    ln -s $BASE_BUILD_DIR $HOME/grappa
  fi
}

install_grappa() {
  # run only on build node

  export LD_LIBRARY_PATH=$DATADIR/build/openmpi/lib
  export PATH=$PATH:$DATADIR/build/openmpi/bin

  INSTALL_DIR=$DATADIR/build/grappa
  if [ ! -e $INSTALL_DIR ]; then
    mkdir -p $INSTALL_DIR
    cd ${BASE_BUILD_DIR}/grappa/build/Make+Release
    sudo make install
    sudo find $INSTALL_DIR -type f -exec chmod g+rw {} \;
    sudo find $INSTALL_DIR -type d -exec chmod g+rwx {} \;
  fi
}


# set GRAPPA_PREFIX for users that log in
cat <<EOF | sudo tee /etc/profile.d/grappa.sh > /dev/null
#!/bin/bash
export GRAPPA_PREFIX=$DATADIR/build/grappa
EOF
sudo chmod +x /etc/profile.d/grappa.sh

# default machinefile
HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
cat <<EOF | sudo tee $DATADIR/build/openmpi/etc/openmpi-default-hostfile > /dev/null
$(for each in $HOSTS; do echo $each; done)
EOF

# Start the builds. This is a pretty bad hack to use an NFS share for synchronization. 
# However this profile is really just for experimental use and in the worst case,
# both nodes will start building.
if [ -e $DATADIR/build_node ]; then
  # we lost the race and are not the build node
  wait_for_build

  # now openmpi is built
  if [[ "$(uname -m)" =~ aarch64.* ]]; then
    echo "Skipping grappa build on ARM"
  else
    build_grappa
  fi

  # copy the munge key into local /etc
  if [ ! -e /etc/munge/munge.key ]; then
    sudo cp $DATADIR/keys/munge.key /etc/munge/
    sudo chown munge:munge /etc/munge/munge.key
  fi
else
  # this is the build node. lock out other nodes
  echo $HOSTNAME > $DATADIR/build_node
  # can't exit while holding lock
  set +e

  build_openmpi
  if [[ "$(uname -m)" =~ aarch64.* ]]; then
    echo "Skipping grappa build on ARM"
  else
    build_grappa
    install_grappa
  fi

  # create the munge key and put it in project dir for other nodes
  if [ ! -e $DATADIR/keys/munge.key ]; then
    if [ ! -e /etc/munge/munge.key ]; then
       sudo /usr/sbin/create-munge-key
    fi
    mkdir $DATADIR/keys
    sudo cp /etc/munge/munge.key $DATADIR/keys/
  elif [ ! -e /etc/munge/munge.key ]; then
    sudo cp $DATADIR/keys/munge.key /etc/munge/
    sudo chown munge:munge /etc/munge/munge.key
  fi

  # release lock
  rm $DATADIR/build_node
  set -e
fi


if [[ "$(cat /etc/lsb-release | grep DISTRIB_RELEASE)" =~ 14 ]]; then
  # slurm setup
  if [ ! -e /etc/slurm-llnl/slurm.conf ]; then
    cd $DATADIR/sources
    wget https://git.cs.colorado.edu/caldweba/cloudlab-setup/raw/master/slurm.conf
    sudo mv slurm.conf /etc/slurm-llnl/slurm.conf
  fi
  sudo update-rc.d slurm-llnl enable
else
  echo "*************************************************"
  echo "Slurm only supported on Ubuntu 14.04. Skipping..."
  echo "*************************************************"
fi

# permissions required for munge to start
sudo chmod o-rwx /var/log/munge
sudo update-rc.d munge enable &> /dev/null

# set environment variables including non-interactive shells for this user
BASHRC=$HOME/.bashrc
if [[ "$(cat $BASHRC | head -2 | grep -c openmpi)" -ne 2 ]]; then
  sed -i '/openmpi/d' $BASHRC
  sed -i "1 i\export LD_LIBRARY_PATH=$DATADIR/build/openmpi/lib" $BASHRC
  sed -i "1 i\export PATH=\$PATH:$DATADIR/build/openmpi/bin" $BASHRC
fi

# do the same for all users who's bashrc might get created later
BASHRC=/etc/bash.bashrc
if [[ "$(cat $BASHRC | head -2 | grep -c openmpi)" -ne 2 ]]; then
  sudo sed -i '/openmpi/d' $BASHRC
  sudo sed -i "1 i\export LD_LIBRARY_PATH=$DATADIR/build/openmpi/lib" $BASHRC
  sudo sed -i "1 i\export PATH=\$PATH:$DATADIR/build/openmpi/bin" $BASHRC
fi

echo "********************************************************"
echo "Finished setting up grappa."
echo "Log out and back in for environment variables to get set"
echo "********************************************************"
