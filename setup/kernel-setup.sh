#!/bin/bash  


if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

build_kernel_ubuntu() {
  set +e
  echo "**************************************************"

  echo "Building Linux kernel 4.20 with userfaultfd extensions..." 
  cd $HOME
  KERNEL_VERSION="4.20-rc7"
  git clone https://github.com/blakecaldwell/userfault-kernel.git kernel-4.20+
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/kernel-config-4.20 &> /dev/null
  cp kernel-config-4.20 kernel-${KERNEL_VERSION}+/.config
  cd kernel-${KERNEL_VERSION}+
  git checkout userfault_${KERNEL_VERSION}
  make olddefconfig
  make -j15 deb-pkg
  echo "done" 
  set +e
}

install_kernel_ubuntu() {
  echo "**************************************************"

  echo "Installing Linux kernel 4.20 with userfaultfd extensions..."
  cd $HOME
  sudo dpkg -i linux-headers-4.20.0+_4.20.0+-1_amd64.deb linux-libc-dev_4.20.0+-1_amd64.deb linux-image-4.20.0+_4.20.0+-1_amd64.deb 
  sudo update-grub2
  echo "done" set +e
  echo "**************************************************"

}

install_kernel_centos() {
  set -e
  cd $HOME
  git clone https://github.com/blakecaldwell/userfault-kernel.git
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/kernel-config-4.20 &> /dev/null
  cp kernel-config-4.20 userfault-kernel/.config
  cd userfault-kernel
  git checkout userfault_4.20
  make olddefconfig
  echo "**************************************************"
  echo "Building Linux kernel 4.20 with userfaultfd extensions..." 
  make -j16 rpm-pkg > /dev/null 2>&1
  echo "done"
  echo "**************************************************"
  echo "Installing Linux kernel 4.20 with userfaultfd extensions..." 
  sudo rpm -e --nodeps kernel-headers
  sudo rpm -ivh ~/rpmbuild/RPMS/x86_64/kernel-*
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg
  echo "done"
  echo "**************************************************"

  set +e
}


if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  export DEBIAN_FRONTEND=noninteractive

  # make sure all commamds succeed
  set -e
  sudo apt-get update
  sudo apt-get install -y build-essential libncurses5-dev gcc libssl-dev grub2 bc
  build_kernel_ubuntu

  install_kernel_ubuntu

elif [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  sudo yum groupinstall -y "Development Tools" &&     yum install -y     openssl     openssl-devel     bison     flex     make     gcc     hmaccalc     zlib-devel     binutils-devel     elfutils-libelf-devel     ncurses-devel     rpm-build     bc     git &&     yum clean all
  if [[ ! "$(uname -r)" =~ 4.20 ]]; then
    sudo yum update
    if [[ "$(uname -m)" =~ aarch64.* ]]; then
      echo "**************************************************"
      echo "WARNING: fluidmem not supported on ARM"
      echo "**************************************************"
    else
      #build_kernel_centos
      install_kernel_centos
    fi

    # make sure all commamds succeed
    set -e
 
    REBOOT=yes
  fi
fi 


# Build on SSD if set by phase1
if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/kernel-4.20+
  if [ ! -e $BUILD_DIR ]; then
    sudo mkdir -p $BUILD_DIR
    sudo chown $USER:$(id -g) $BUILD_DIR
    ln -s $BUILD_DIR $HOME/kernel-4.20+
  fi
else
  BUILD_DIR=$HOME/kernel-4.20+
  if [ ! -e $BUILD_DIR ]; then
    mkdir $BUILD_DIR
  fi
fi

#if [ ! -e $BUILD_DIR/.git ]; then
#  build_kernel
#fi

# let other installs continue
rm -f /tmp/kernel-lock

echo "*************************************************************"
echo "Finished updating kernel"
echo "REBOOT NEEDED."
echo "*************************************************************"
