# FluidMem CloudLab profile

Blake Caldwell <caldweba@colorado.edu>

University of Colorado at Boulder

April 19, 2019

## Prerequisites
 - A cloudlab.us account
 - Membership in a project. Start a new project: https://cloudlab.us/signup.php

## Instantiating an experiment
 1. Go to https://www.cloudlab.us/p/99fca391-3dd1-11e9-897b-e4434b2381fc
 2. Follow the prompts, choosing the number of nodes and the OS distro. Any of the available
    clusters should work for this profile, but typically Utah APT has the most nodes free.
    The emulab cluster has much older hardware.

## Once cluster has started
 - Login to the node with the ssh key provided to cloudlab
 - Check logs in /root/setup to see which phases have completed. The script can be run manually:

```bash
sudo /tmp/setup/phase1-setup.sh
```

- Run phase2 command. This can be run in parallel across all nodes in the cluster using pdsh

```bash
pdsh -w cp-[1-2] /tmp/setup/phase2-setup.sh all
```

- Since the kernel was updated, you will need to reboot all machines (from pdsh)

```bash
pdsh -w cp-[1-2] sudo reboot
```

## Starting FluidMem

FluidMem's monitor service can be started on any node in the cluster. It will connect to the coordinator with the LOCATOR variable defined below. The Zookeeper connect location  is also necessary, but any server part of the cluster should work. Below we use the master (cp-1) again.
```bash
ZOOKEEPER=zk:$LOCATOR
LOCATOR=zk:10.0.1.1:2181
# set default cache size to 20,000 pages (80MB)
CACHE_SIZE=20000
# monitor will run in the foreground
monitor $LOCATOR --zookeeper=${ZOOKEEPER} --cache_size=${CACHE_SIZE} --print_info
```

## Starting ramcloud

Note that fluidmem will need to be reconfigured and compiled with --enable-ramcloud instead of --enable-noop

After configuration, the interface ib0 should be up with an IP address in the 10.0.0.0/24 network. This is the interface that ramcloud will use. If the interface was successfully created during, boot, then the ramcloud sevices likely have already started. If not, you$ start them manually:

From cp-1 (the coordinator):
```bash
sudo systemctl restart ramcloud-coordinator
sudo systemctl restart ramcloud-server
```

From cp-2:
```bash
sudo systemctl restart ramcloud-server

# verify server 2.0 (cp-2) has started
sudo journalctl -f -u ramcloud-server
```
