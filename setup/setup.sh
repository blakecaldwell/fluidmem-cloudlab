#!/bin/bash

###############
# setup.sh
#
# Blake Caldwell <caldweba@colorado.edu>
# May 1st, 2020
#
# Purpose: setup script for cloudlab systems
#  Type fluidmem
#            1. install 5.6 kernel with userfaultfd support
#            2. install fluidmem and start monitor
#            3. build ramcloud and start ramcloud-coordinator
#  Type infiniswap
#            1. install 4.10.17 kernel with userfaultfd support
#            2. install MLNX OFED 4.1 support
#            3. compile infiniswap bd/daemon
#  Type combined
#            1. install 4.10.17 kernel with userfaultfd support
#            2. all of the rest of the above
###############

die() { echo "$@" 1>&2 ; exit 1; }

SUPPORTED_TYPES=(fluidmem infiniswap base)
ARGS=("$@")
[[ $ARGS ]] || die "No setup type specified. Supported types: ${SUPPORTED_TYPES[@]}"

NEW_ARGS=()

for TYPE in "${ARGS[@]}"; do
  if [[ " ${SUPPORTED_TYPES[@]} " =~ " $TYPE " ]]; then
    NEW_ARGS+=( "$TYPE" )
  else
    echo "$TYPE is not a supported argument. Options are ${SUPPORTED_TYPES[@]}"
  fi
done

FLAG="/opt/.usersetup"
SETUPFLAG="/opt/.setup_in_process"
# FLAG will not exist on the *very* fist boot because
# it is created here!
if [ ! -f $SETUPFLAG ]; then
   touch $SETUPFLAG
   touch $FLAG
fi

HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
let i=0
for each in $HOSTS; do
  (( i += 1 ))
done

cat <<EOF | tee /etc/profile.d/firstboot.sh > /dev/null
#!/bin/bash

if [ -f $SETUPFLAG ]; then
  echo "*******************************************"
  echo "Setup in progress. Wait until complete"
  echo "before installing any packages"
  echo "*******************************************"

elif [ -f $FLAG ]; then
  if [ -z "$HOSTS" ]; then
  # single host in cluster
    echo "***********************************************************"
    echo -e "Setup complete"
    echo "***********************************************************"

  else

    echo "***********************************************************************************"
    echo -e "Setup complete"
    echo -e "Your cluster has the following hosts:\n\
$HOSTS\n"
    echo "You can run commands on all hosts in parallel with pdsh. For example:"
    echo "pdsh -w cp-[1-$i] hostname"
    echo "***********************************************************************************"

  fi
fi
EOF
chmod +x /etc/profile.d/firstboot.sh


sudo /opt/setup/phase1-setup.sh

# UBUNTU_RELEASE=$(cat /etc/lsb-release |grep DISTRIB_RELEASE|cut -d'=' -f2)
# if [ -z $UBUNTU_RELEASE ]; then
#   die "Error: could not detect Ubuntu release from /etc/lsb-release"
# fi

if [[ "${NEW_ARGS[@]}" =~ fluidmem ]] && [[ "${NEW_ARGS[@]}" =~ infiniswap ]]; then
  bash -x /opt/setup/kernel-setup.sh 4.10.17 && \
  bash -x /opt/setup/ramcloud-setup.sh && \
  bash -x /opt/setup/fluidmem-setup.sh && \
  bash -x /opt/setup/infiniswap-setup.sh && \
  bash -x /opt/setup/base-setup.sh
elif [[ "${NEW_ARGS[@]}" =~ fluidmem ]]; then
  bash -x /opt/setup/kernel-setup.sh 5.6 && \
  bash -x /opt/setup/ramcloud-setup.sh && \
  bash -x /opt/setup/fluidmem-setup.sh && \
  bash -x /opt/setup/base-setup.sh
elif [[ "${NEW_ARGS[@]}" =~ infiniswap ]]; then
  bash -x /opt/setup/kernel-setup.sh 4.10.17 && \
  bash -x /opt/setup/infiniswap-setup.sh && \
  bash -x /opt/setup/base-setup.sh
elif [[ "${NEW_ARGS[@]}" =~ base ]]; then
  bash -x /opt/setup/base-setup.sh
fi

if [ $? -ne 0 ]; then
  echo "**********************************************************************************"
  echo "There was an error setting up modules \"${NEW_ARGS[@]}\". Try re-running individual modules."
  echo "If errors persist, run:"
  for TYPE in "${NEW_ARGS[@]}"; do
    echo "bash -x /opt/setup/$TYPE-setup.sh | tee -a /opt/$TYPE-err.log"
  done
  echo
  echo "Then start an issue at https://www.github.com/blakecaldwell/fluidmem-cloudlab/issues"
  echo "with the log file attached"
  echo "**********************************************************************************"
  exit 2
fi

if [ ! -e /opt/setup/.setup_completed ]; then
  touch /opt/setup/.setup_completed
else
  echo "Setup has already completed"
  exit 0
fi

# FLAG="/opt/.usersetup"
# if [ ! -e $FLAG ]; then
#   # Have already been warned about reboot. This might be a second module install
#   exit 0
# fi

# sudo rm -f $FLAG

rm -f $SETUPFLAG


#   echo "You must reboot all systems for changes to take effect"
#   echo "pdsh -w cp-[1-$i] sudo reboot"
#   echo "Note: the message \"Failed to connect to bus: Connection refused\""
#   echo "is expected. The system will still reboot."
# else
#   echo "You must reboot the system for changes to take effect"
# fi
# echo "********************************************************************"
