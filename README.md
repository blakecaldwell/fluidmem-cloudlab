# FluidMem CloudLab profile

Blake Caldwell <caldweba@colorado.edu>

University of Colorado at Boulder

March 3, 2019

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
 - A message at login will print out a command to run to start phase 2. This command can be run in parallel across all nodes in the cluster using pdsh
 - The script may instruct you to reboot the machine afterwards. This would need to be done on all systems in the cluster (again using pdsh)
