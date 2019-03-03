#!/bin/bash  

if [[ $EUID -eq 0 ]]; then
  echo "This script should be run as a regular user, not with sudo!"
  exit 1
fi

custom_deb_kernel() {
  set -e

  cd /tmp
  wget https://csel.cs.colorado.edu/~caldweba/cloudlab-setup/linux-4.3.0-dax.tar.xz &> /dev/null
  tar -xf linux-4.3.0-dax.tar.xz
  cd linux-dax
  echo "**************************************************"
  echo "Installing Linux kernel 4.3 with DAX extensions..." 
  sudo dpkg -i *.deb
  echo "done"
  echo "**************************************************"

  set +e
}

upgrade1604() {
  echo "****************************************************"
  echo "Starting upgrade to Ubuntu development release 16.04"
#  echo "Prompts will require user input. Just press enter to accept defaults"
  echo "***************************************************"
  sudo /usr/bin/do-release-upgrade -m server -d -f DistUpgradeViewNonInteractive &> /dev/null
  #sudo /usr/bin/do-release-upgrade -m server -d
    
  echo "**********************************************"
  echo "Upgrade to Ubuntu 16.04 finished. Cleaning up."
  echo "**********************************************"
  sudo DEBIAN_FRONTEND=noninteractive dpkg --force-depends -P libplymouth2 plymouth plymouth-disabler plymouth-theme-ubuntu-text mountall libfontconfig1 fontconfig-config fontconfig
  sudo DEBIAN_FRONTEND=noninteractive apt-get -fy install
  sudo DEBIAN_FRONTEND=noninteractiv eapt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install grub
  sudo update-grub -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install sysv-rc friendly-recovery kexec-tools memtest86+ python3.4-minimal
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install -f
  sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y --force-yes -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" dist-upgrade
}

if [[ "$(cat /etc/redhat-release)" =~ CentOS.* ]]; then
  NOBODY_USR_GRP="nobody:nobody"
  echo "CentOS pmem install not supported yet. Exiting..."
  exit 1
elif [[ "$(cat /etc/lsb-release | grep DISTRIB_ID)" =~ .*Ubuntu.* ]]; then
  if [[ ! "$(uname -r)" =~ 4.3 ]]; then
    sudo apt-get update
    if [[ "$(uname -m)" =~ aarch64.* ]]; then
      echo "**************************************************"
      echo "WARNING: The nvml library will not compile on ARM."
      echo "Installing 16.04 kernel and dependencies anyway"
      echo "**************************************************"
      upgrade1604
    else
      upgrade1604
      #custom_deb_kernel
    fi

    # make sure all commamds succeed
    set -e
    sudo DEBIAN_FRONTEND=noninteractive apt-get -q -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install uuid-dev vim
    NOBODY_USR_GRP="nobody:nogroup"
 
    echo "Setting compiler to GCC 4.8"
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 60 --slave /usr/bin/g++ g++ /usr/bin/g++-4.8
    sudo update-alternatives --set gcc /usr/bin/gcc-4.8
 
    REBOOT=yes
  fi
fi 

if [[ "$(uname -m)" =~ aarch64.* ]]; then
  if ! grep -q memmap /boot/grub/menu.lst; then
    echo "Adding kernel parameter to grub to create /dev/pmem0 as a 16GB ram-'disk'"
    sudo sed -i 's/defoptions=\(.*\)$/defoptions=\1 memmap=16G!16G/' /boot/grub/menu.lst
    sudo DEBIAN_FRONTEND=noninteractive update-grub-legacy-ec2
  fi
else
  if ! grep -q memmap /boot/grub/grub.cfg; then
    echo "Adding kernel parameter to grub to create /dev/pmem0 as a 16GB ram-'disk'"
    sudo sed -i 's/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX="memmap=16G!16G \1\"/'  /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  fi
fi

# let other installs continue
rm -f /tmp/pmem-lock
  
# script to mount pmem deive
cat <<EOF  | sudo tee /usr/local/bin/mount-pmem.sh > /dev/null
#!/bin/bash
  
set -e
MNT=/pmem-fs

if [ ! -e /dev/pmem0 ]; then
  echo "Could not find pmem device. Has kernel cmdline been updated to create it on boot?"
  exit 1
elif mount | grep -q pmem0; then
  echo "pmem0 already mounted"
  exit 1
fi
sudo parted -s /dev/pmem0 mklabel gpt -- mkpart ext3 1MiB 100%
sudo mkfs.ext4 /dev/pmem0p1
  
if [ ! -d \$MNT ]; then
  sudo mkdir \$MNT
fi
sudo mount -o dax /dev/pmem0p1 \$MNT
sudo chmod 1777 \$MNT
EOF
sudo chmod +x /usr/local/bin/mount-pmem.sh

# Run on boot
if ! grep -q pmem-fs /etc/rc.local; then
  echo "echo \"Mounting pmem filesystem at /pmem-fs\"" | sudo tee -a /etc/rc.local > /dev/null
  echo "/usr/local/bin/mount-pmem.sh" | sudo tee -a /etc/rc.local > /dev/null
fi

# Build on SSD if set by phase1
if [ -n "$SSD" ] && [ -e /dev/$SSD ]; then
  BUILD_DIR=/ssd/build/nvml
  if [ ! -e $BUILD_DIR ]; then
    sudo mkdir -p $BUILD_DIR
    sudo chown $USER:$(id -g) $BUILD_DIR
    ln -s $BUILD_DIR $HOME/nvml
  fi
else
  BUILD_DIR=$HOME/nvml
  if [ ! -e $BUILD_DIR ]; then
    mkdir $BUILD_DIR
  fi
fi

build_nvml() {
  echo "Cloning and building nvml in ${BUILD_DIR}"
  git clone https://github.com/pmem/nvml.git ${BUILD_DIR}
  if [[ "$(uname -m)" =~ aarch64.* ]]; then
    echo "Skipping nvml install on aarch64"
    exit 0
  fi
  cd ${BUILD_DIR}
  make
  sudo make install
}

if [ ! -e $BUILD_DIR/.git ]; then
  build_nvml
fi

echo "*************************************************************"
echo "Finished upgrading kernel and building nvml (pmem.io library)"
echo "REBOOT NEEDED. /usr/local/bin/mount-pmem.sh will run to"
echo "mount pmem ramdisk filesystem at /pmem-fs/"
echo "*************************************************************"
