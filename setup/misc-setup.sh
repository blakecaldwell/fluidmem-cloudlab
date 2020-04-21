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
  UBUNTU_RELEASE=$(cat /etc/lsb-release |grep DISTRIB_RELEASE|cut -d'=' -f2)
  if [ -z $UBUNTU_RELEASE ]; then
    die "Error: could not detect Ubuntu release from /etc/lsb-release"
  fi

  if [[ "$UBUNTU_RELEASE" =~ "14.04" ]]; then
    sudo apt-get install -y uuid-dev
  fi
  sudo apt-get install -y libxml2-dev libxslt1-dev

  sudo apt-get install -y cgroup-bin cgroup-lite libcgroup1
  sudo cgcreate -g memory:/myGroup
  sudo cgset -r memory.limit_in_bytes=1m myGroup
  echo "*:pmbench memory myGroup" | sudo tee /etc/cgrules.conf

  cat <<EOF | sudo tee /etc/cgconfig.conf > /dev/null
# Since systemd is working well, this section may not be necessary.
# Uncomment if you need it
#
# mount {
# cpuacct = /cgroup/cpuacct;
# memory = /cgroup/memory;
# devices = /cgroup/devices;
# freezer = /cgroup/freezer;
# net_cls = /cgroup/net_cls;
# blkio = /cgroup/blkio;
# cpuset = /cgroup/cpuset;
# cpu = /cgroup/cpu;
# }

group limitcpu{
  cpu {
    cpu.shares = 400;
  }
}

group limitmem{
  memory {
    memory.limit_in_bytes = 512m;
  }
}

group limitio{
  blkio {
    blkio.throttle.read_bps_device = "252:0         2097152";
  }
}

group browsers {
    cpu {
#       Set the relative share of CPU resources equal to 25%
    cpu.shares = "256";
}
memory {
#       Allocate at most 512M of memory to tasks
        memory.limit_in_bytes = "512m";
#       Apply a soft limit of 512 MB to tasks
        memory.soft_limit_in_bytes = "384m";
    }
}

group media-players {
    cpu {
#       Set the relative share of CPU resources equal to 25%
        cpu.shares = "256";
    }
    memory {
#       Allocate at most 256M of memory to tasks
        memory.limit_in_bytes = "256m";
#       Apply a soft limit of 196 MB to tasks
        memory.soft_limit_in_bytes = "128m";
    }
}
EOF

  sudo cgrulesengd
fi

cd $HOME
git clone --branch userfault https://github.com/blakecaldwell/pmbench.git
cd pmbench
make pmbench

# let other installs continue
rm -f /tmp/misc-lock

echo "*********************************"
echo "Finished setting up Misc"
echo "*********************************"

