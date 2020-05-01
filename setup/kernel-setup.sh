#!/bin/bash  

die() { echo "$@" 1>&2 ; exit 1; }

if [ -e /opt/.kernel-installed ]; then
  echo "Already installed kernel"
  exit 0
fi

SUPPORTED_TYPES=(4.10.17 5.1 5.6 4.20-rc7 )
ARGS=("$@")
[[ $ARGS ]] || die "No valid kernel specified. Supported versions: ${SUPPORTED_TYPES[@]}"

if [ $# -gt 1 ]; then
  die "Only one kernel can be selected. Supported versions: ${SUPPORTED_TYPES[@]}"
fi

KERNEL_VERSION="$1"

sudo chmod 777 /opt
sudo chown $(id -u):$(id -g) /opt

DPKG_DIR=/opt
if [ -e /mnt/second_drive ]; then
  sudo chown $(id -u):$(id -g) /mnt/second_drive
  BUILD_DIR=/mnt/second_drive/userfault-kernel
  if [ ! -e $BUILD_DIR ]; then
    sudo mkdir -p $BUILD_DIR
    sudo chown -R $(id -u):$(id -g) $BUILD_DIR
  fi
  if [ ! -e /opt/userfault-kernel ]; then
    ln -s $BUILD_DIR /opt/userfault-kernel
  fi
  DPKG_DIR=/mnt/second_drive/
fi

UBUNTU_RELEASE=$(cat /etc/lsb-release |grep DISTRIB_RELEASE|cut -d'=' -f2)

build_kernel_ubuntu() {
  set -e
  KERNEL_VERSION="$1"
  echo "**********************************************************************"
  echo "Building Linux kernel ${KERNEL_VERSION} with userfaultfd extensions..."
  cd /opt
  if [[ "$KERNEL_VERSION" == "4.10.17" ]]; then
    if [[ "$UBUNTU_RELEASE" =~ "16.04" ]]; then
      git clone git://kernel.ubuntu.com/ubuntu/ubuntu-xenial.git userfault-kernel
    else
      die "Ubuntu release $UBUNTU_RELEASE is not supported for kernel version ${KERNEL_VERSION}"
    fi
    cd userfault-kernel
    git checkout Ubuntu-hwe-4.10.0-43.47_16.04.1
    git remote add userfault https://github.com/blakecaldwell/userfault-kernel.git
    git fetch userfault userfault_$KERNEL_VERSION
    git cherry-pick d8bb9f6f9b^..16f11aaf4a
    FAKEROOT=fakeroot
  else
    git clone https://github.com/blakecaldwell/userfault-kernel.git userfault-kernel
    cd userfault-kernel
    git checkout userfault_${KERNEL_VERSION}
    FAKEROOT=
  fi
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/kernel-config-${KERNEL_VERSION} &> /dev/null
  cp kernel-config-${KERNEL_VERSION} .config
  make olddefconfig
  $FAKEROOT make -j15 deb-pkg LOCALVERSION=-userfault-nvmef KDEB_PKGVERSION=1
  echo "done" 
  echo "**********************************************************************"
  set +e
}

install_kernel_ubuntu() {
  set -e
  echo "**********************************************************************"

  echo "Installing Linux kernel ${KERNEL_VERSION} with userfaultfd extensions..."
  cd /opt
  sudo dpkg -i $DPKG_DIR/linux-*${KERNEL_VERSION}*.deb
  HEADERFILE=$(dpkg -L $(dpkg -l |grep linux-headers-5.6| awk '{print $2}') |grep uapi|grep userfaultfd.h)
  sudo cp $HEADERFILE /usr/include/linux/userfaultfd.h 
  sudo update-grub
  echo "Disabling smt in kernel..."
  sudo sed -i 's/\(^GRUB_CMDLINE_LINUX=.*\)"$/\1 nosmt"/' /etc/default/grub
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  sudo grub-install --force /dev/sda1
  echo "done"
  echo "**********************************************************************"
  set +e
}

install_kernel_centos() {
  set -e
  cd /opt
  git clone https://github.com/blakecaldwell/userfault-kernel.git
  wget https://raw.githubusercontent.com/blakecaldwell/fluidmem-cloudlab/master/setup/kernel-config-4.20 &> /dev/null
  cp kernel-config-4.20 userfault-kernel/.config
  cd userfault-kernel
  git checkout userfault_4.20
  make olddefconfig
  echo "**********************************************************************"
  echo "Building Linux kernel 4.20 with userfaultfd extensions..." 
  make -j16 rpm-pkg > /dev/null 2>&1
  echo "done"
  echo "**********************************************************************"
  echo "Installing Linux kernel 4.20 with userfaultfd extensions..." 
  sudo rpm -e --nodeps kernel-headers
  sudo rpm -ivh ~/rpmbuild/RPMS/x86_64/kernel-*
  sudo grub2-mkconfig -o /boot/grub2/grub.cfg
  echo "done"
  echo "**********************************************************************"

  set +e
}

#if [ ! -e $BUILD_DIR/.git ]; then
#  build_kernel
#fi

set -e
if [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  export DEBIAN_FRONTEND=noninteractive

  cd /opt
  sudo apt-get update
  sudo apt-get install -y build-essential libncurses5-dev gcc libssl-dev grub2 bc
  build_kernel_ubuntu $KERNEL_VERSION

  # clear up some space
  echo "Removing $BUILD_DIR to free up space"
  sudo rm -rf $BUILD_DIR
  install_kernel_ubuntu

elif [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  sudo yum groupinstall -y "Development Tools" &&     yum install -y     openssl     openssl-devel     bison     flex     make     gcc     hmaccalc     zlib-devel     binutils-devel     elfutils-libelf-devel     ncurses-devel     rpm-build     bc     git &&     yum clean all
  if [[ ! "$(uname -r)" =~ 4.20 ]]; then
    sudo yum update
    #build_kernel_centos
    # clear up some space
    echo "Removing $BUILD_DIR to free up space"
    sudo rm -rf $BUILD_DIR

    install_kernel_centos
  fi
fi 

sudo touch /opt/.kernel-installed

# let other installs continue
rm -f /tmp/kernel-lock

echo "*************************************************************"
echo "Finished updating kernel"
echo "Rebooting..."
echo "*************************************************************"
sudo reboot