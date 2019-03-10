#!/bin/bash

###############
# phase2-setup.sh
#
# Blake Caldwell <caldweba@colorado.edu>
# December 11th, 2015
#
# Purpose: setup script for cloudlab systems
#  Type fluidmem
#            1. install 4.20 kernel with userfaultfd support
#            2. install fluidmem and start monitor
#            3. build ramcloud and start ramcloud-coordinator
#  Type ramcloud
#            1. build ramcloud and start ramcloud-server
###############

die() { echo "$@" 1>&2 ; exit 1; }

if [[ $EUID -eq 0 ]]; then
  die "This script should be run as a regular user, not with sudo!"
fi

SUPPORTED_TYPES="kernel docker fluidmem ramcloud misc all"

[[ $1 ]] || die "No setup type specified. Supported types: ${SUPPORTED_TYPES}"

TYPE=$1

if [[ ! ${SUPPORTED_TYPES} =~ .*$TYPE.* ]]; then
  die "Type $TYPE not supported. Supported types: ${SUPPORTED_TYPES}"
fi

if [ $TYPE == "kernel" ]; then
  /usr/local/bin/kernel-setup.sh
elif [ $TYPE == "ramcloud" ]; then
  /usr/local/bin/ramcloud-setup.sh
elif [ $TYPE == "fluidmem" ]; then
  /usr/local/bin/fluidmem-setup.sh
elif [ $TYPE == "docker" ]; then
  /usr/local/bin/docker-setup.sh
elif [ $TYPE == "misc" ]; then
  /usr/local/bin/misc-setup.sh
elif [ $TYPE == "all" ]; then
  touch /tmp/kernel-lock
  /usr/local/bin/kernel-setup.sh &
  while [ -e /tmp/kernel-lock ]; do
    sleep 1 
  done

  touch /tmp/ramcloud-lock
  /usr/local/bin/ramcloud-setup.sh &
  while [ -e /tmp/ramcloud-lock ]; do
    sleep 1
  done

  touch /tmp/docker-lock
  /usr/local/bin/docker-setup.sh &
  while [ -e /tmp/docker-lock ]; do
    sleep 1
  done

  touch /tmp/misc-lock
  /usr/local/bin/misc-setup.sh &
  while [ -e /tmp/misc-lock ]; do
    sleep 1
  done

  /usr/local/bin/fluidmem-setup.sh &

  wait
fi

if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error setting up module \"$TYPE\". Try re-running individual modules."
  echo "If errors persist, run:"
  echo "bash -x /usr/local/bin/$TYPE-setup.sh | tee /tmp/$TYPE-err.log"
  echo
  echo "Then start an issue at https://www.github.com/blakecaldwell/fluidmem-cloudlab/issues"
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
  echo "You must reboot all systems for changes to take effect"
  echo "pdsh -w cp-[1-$i] sudo reboot"
  echo "Note: the message \"Failed to connect to bus: Connection refused\""
  echo "is expected. The system will still reboot."
else
  echo "You must reboot the system for changes to take effect"
fi
echo "********************************************************************"
