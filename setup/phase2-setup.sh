#!/bin/bash

###############
# phase2-setup.sh
#
# Blake Caldwell <caldweba@colorado.edu>
# December 11th, 2015
#
# Purpose: setup script for cloudlab systems
#  Type pmem:
#            1. install 4.3 kernel with pmem support
#               - Centos 7.1 -- TODO
#            2. install package dependencies and build nvml library
#  Type grappa:
#            1. Build openmpi
#            2. Build grappa
#  Type accelio:
#            1. Clone and build xio library
###############

die() { echo "$@" 1>&2 ; exit 1; }

if [[ $EUID -eq 0 ]]; then
  die "This script should be run as a regular user, not with sudo!"
fi

SUPPORTED_TYPES="pmem accelio grappa all"

[[ $1 ]] || die "No setup type specified. Supported types: ${SUPPORTED_TYPES}"

TYPE=$1

if [[ ! ${SUPPORTED_TYPES} =~ .*$TYPE.* ]]; then
  die "Type $TYPE not supported. Supported types: ${SUPPORTED_TYPES}"
fi

if [ $TYPE == "pmem" ]; then
  /usr/local/bin/pmem-setup.sh
elif [ $TYPE == "accelio" ]; then
  /usr/local/bin/accelio-setup.sh
elif [ $TYPE == "grappa" ]; then
  /usr/local/bin/grappa-setup.sh
elif [ $TYPE == "all" ]; then
  touch /tmp/pmem-lock
  /usr/local/bin/pmem-setup.sh &
  while [ -e /tmp/pmem-lock ]; do
    sleep 1 
  done

  touch /tmp/grappa-lock
  /usr/local/bin/grappa-setup.sh &
  while [ -e /tmp/grappa-lock ]; do
    sleep 1
  done

  /usr/local/bin/accelio-setup.sh &
  wait
fi
if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error setting up module \"$TYPE\". Try re-running individual modules."
  echo "If errors persist, run:"
  echo "bash -x /usr/local/bin/$TYPE-setup.sh | tee /tmp/$TYPE-err.log"
  echo
  echo "Then start an issue at https://git.cs.colorado.edu/caldweba/cloudlab-setup/issues"
  echo "with the log file attached"
  echo "**********************************************************************************"
  exit 2
fi


FLAG="/opt/.usersetup"
if [ ! -e $FLAG ]; then
  # Have already been warned about reboot. This might be a second module install
  exit 0
fi

sudo rm -f $FLAG
HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
let i=0
for each in $HOSTS; do
  (( i += 1 ))
done

echo "********************************************************************"
if [ -n "$HOSTS" ]; then
  echo "You must reboot all systems for RDMA changes to take effect"
  echo "pdsh -w cp-[1-$i] sudo reboot"
  echo "Note: the message \"Failed to connect to bus: Connection refused\""
  echo "is expected. The system will still reboot."
else
  echo "You must reboot the system for RDMA changes to take effect"
fi
echo "********************************************************************"
