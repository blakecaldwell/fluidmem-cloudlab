#!/bin/bash

for cpu in $(seq 0 15); do   echo performance > /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor; done
modprobe nvmet
modprobe nvmet-rdma
mkdir /sys/kernel/config/nvmet/subsystems/fluidmem
cd /sys/kernel/config/nvmet/subsystems/fluidmem
echo 1 > attr_allow_any_host
mkdir namespaces/10
echo -n /dev/pmem0 > namespaces/10/device_path
echo 1 > namespaces/10/enable
mkdir /sys/kernel/config/nvmet/ports/1
cd /sys/kernel/config/nvmet/ports/1
export ip=$(ip a show dev ib0|grep inet|grep -v inet6|awk '{print $2}'|sed 's/\(.*\)\/.*/\1/')
echo $ip > addr_traddr
echo rdma > addr_trtype
echo 4420 > addr_trsvcid
echo ipv4 > addr_adrfam
ln -s /sys/kernel/config/nvmet/subsystems/fluidmem /sys/kernel/config/nvmet/ports/1/subsystems/fluidmem

