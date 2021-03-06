#!/usr/bin/env python

import geni.portal as portal
import geni.rspec.pg as rspec
import geni.rspec.igext as IG
from lxml import etree as ET
import crypt
import random

# Don't want this as a param yet
TBURL = "https://www.github.com/blakecaldwell/fluidmem-cloudlab/raw/master/setup.tar.gz"

BASE_CMD = "/opt/setup/setup.sh base | sudo tee -a /opt/setup/setup.log"
FLUIDMEM_CMD = "/opt/setup/setup.sh base fluidmem | sudo tee -a /opt/setup/setup.log"
INFINISWAP_CMD = "/opt/setup/setup.sh base infiniswap | sudo tee -a /opt/setup/setup.log"
COMBINED_CMD = "/opt/setup/setup.sh base fluidmem infiniswap | sudo tee -a /opt/setup/setup.log"
#
# Create our in-memory model of the RSpec -- the resources we're going to request
# in our experiment, and their configuration.
#
request = portal.context.makeRequestRSpec()


#
# Define *many* parameters; see the help docs in geni-lib to learn how to modify.
#
portal.context.defineParameter("computeNodeCount", "Number of compute nodes",
                   portal.ParameterType.INTEGER, 1)
portal.context.defineParameter("FluidMem", "Install FluidMem?",
                   portal.ParameterType.BOOLEAN, True)
portal.context.defineParameter("Infiniswap", "Install Infiniswap?",
                   portal.ParameterType.BOOLEAN, False)
portal.context.defineParameter("hardwareType","Hardware Type",
                   portal.ParameterType.STRING,"c6220",[("c6220","c6220 APT"),("r320","r320 APT"),("c6320","c6320 Clemson"),("d6515","d6515 Utah")],
                   longDescription="Hardware type to request. All have Infiniband.")
portal.context.defineParameter("archType","Architecture Type",
                   portal.ParameterType.STRING,"x86_64",[("arm","ARM"),("x86_64","Intel x86_64")],
                   longDescription="Either ARM64 (X-GENE, aarch64) or Intel x86_64 for the system architecture type.")
portal.context.defineParameter("OSType","OS Type",
                   portal.ParameterType.STRING,"ubuntu16",[("centos","CentOS 7.1"),("ubuntu14","Ubuntu 14.04"),("ubuntu16","Ubuntu 16.04")],
                   longDescription="Choose either CentOS 7.1, Ubuntu 14.04, or Ubuntu 16.04 for the OS distribution.")
portal.context.defineParameter("computeHostBaseName", "Base name of compute node(s)",
                   portal.ParameterType.STRING, "cp", advanced=True,
                   longDescription="The base string of the short name of the compute nodes (node names will look like cp-1, cp-2, ... You shold leave this alone unless you really want the hostname to change.")
portal.context.defineParameter("ipAllocationStrategy","IP Addressing",
                   portal.ParameterType.STRING,"script",[("cloudlab","CloudLab"),("script","This Script")],
                   longDescription="Either let CloudLab auto-generate IP addresses for the nodes, or let this script generate them.  If the script IP address generation is buggy or otherwise insufficient, you can fall back to CloudLab and see if that improves things.",
                   advanced=True)

#
# Get any input parameter values that will override our defaults.
#
params = portal.context.bindParameters()

#
# Verify our parameters and throw errors.
#
if params.computeNodeCount > 8:
    perr = portal.ParameterWarning("Do you really need more than 8 compute nodes?  Think of your fellow users scrambling to get nodes :).",['computeNodeCount'])
    portal.context.reportWarning(perr)
    pass

if params.OSType == 'centos' and params.archType == 'arm':
    perr = portal.ParameterError("ARM architecture type is not compatible with CentOS disk image. Please choose Ubuntu with ARM architecture type.",['OSType','archType'])
    portal.context.reportError(perr)
    pass

if params.ipAllocationStrategy == 'script':
    generateIPs = True
else:
    generateIPs = False
    pass


#
# Give the library a chance to return nice JSON-formatted exception(s) and/or
# warnings; this might sys.exit().
#
portal.context.verifyParameters()


firstNode = "%s-%d" % (params.computeHostBaseName,1)
tourDescription = \
  "A configurable number of nodes for running FluidMem with RDMA libraries and parallel shell (pdsh) installed. The following distributions are valid: " + '\n' + \
  " 1. x86_64 w/ Ubuntu 16.04 (FluidMem)" + '\n' + \
  " 2. x86_64 w/ Ubuntu 14.04 (Infiniswap)" + '\n' + \
  " 3. x86_64 w/ Centos 7.1" + '\n' + \
  "Note: A message at login will be displayed about next steps for configuration (kernel, ramcloud, fluidmem)" + '\n' 

tourInstructions = \
  "Log in with your cloudlab account, authenticating by SSH public key. Follow instructions given by login message."

#
# Setup the Tour info with the above description and instructions.
#  
tour = IG.Tour()
tour.Description(IG.Tour.TEXT,tourDescription)
tour.Instructions(IG.Tour.MARKDOWN,tourInstructions)
request.addTour(tour)

#
# Ok, get down to business -- we are going to create CloudLab LANs to be used as
# (openstack networks), based on user's parameters.  We might also generate IP
# addresses for the nodes, so set up some quick, brutally stupid IP address
# generation for each LAN.
#

ipdb = {}
ipdb['mgmt-lan'] = { 'base':'192.168','netmask':'255.255.0.0','values':[-1,-10,0,0] }

# Assume a /16 for every network
# blakec: this is hacked. don't instantiate more than 255 nodes!
def get_next_ipaddr(lan):
    ipaddr = ipdb[lan]['base']
    backpart = ''

    idxlist = range(2,4)
    idxlist.reverse()
    didinc = False
    for i in idxlist:
        if ipdb[lan]['values'][i] is -1:
            break
        if not didinc:
            didinc = True
            ipdb[lan]['values'][i] += 1
            if ipdb[lan]['values'][i] > 254:
                if ipdb[lan]['values'][i-1] is -1:
                    return ''
                else:
                    ipdb[lan]['values'][i-1] += 1
                    pass
                pass
            pass
        backpart = '.' + str(ipdb[lan]['values'][i]) + backpart
        pass

    return ipaddr + backpart

def get_netmask(lan):
    return ipdb[lan]['netmask']

#
# Ok, also build a management LAN if requested.  If we build one, it runs over
# a dedicated experiment interface, not the Cloudlab public control network.
#
 
mgmtlan = request.LAN('mgmt-lan')
# blakec: always Multiplex any flat networks (i.e., management and all of the flat 
#         data networks) over physical interfaces, using VLANs.
mgmtlan.link_multiplexing = True
mgmtlan.best_effort = True
# Need this cause LAN() sets the link type to lan, not sure why.

#
# Construct the disk image URNs we're going to set the various nodes to load.
#

#x86_ubuntu_disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+emulab-ops//UBUNTU14-64-STD'
x86_ubuntu14_disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU14-64-STD'
x86_ubuntu16_disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops//UBUNTU16-64-STD'
#x86_ubuntu_disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+cloudlab-PG0:x86-ubuntu15-10:0'
#x86_centos_disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops:CENTOS71-64-STD'
x86_centos_disk_image = 'urn:publicid:IDN+emulab.net+image+emulab-ops:CENTOS7-64-STD'
arm_disk_image = 'urn:publicid:IDN+utah.cloudlab.us+image+emulab-ops:UBUNTU14-64-ARM'

if params.OSType == 'centos':
  chosenDiskImage = x86_centos_disk_image
elif params.OSType == 'ubuntu16':
  if params.archType == 'x86_64':
    chosenDiskImage = x86_ubuntu16_disk_image
elif params.OSType == 'ubuntu14':
  if params.archType == 'x86_64':
    chosenDiskImage = x86_ubuntu14_disk_image

computeNodeNames = []
computeNodeList = ""
for i in range(1,params.computeNodeCount + 1):
    cpname = "%s-%d" % (params.computeHostBaseName,i)
    computeNodeNames.append(cpname)
    pass

for cpname in computeNodeNames:
    cpnode = rspec.RawPC(cpname)
    cpnode.hardware_type = params.hardwareType
    cpnode.disk_image = chosenDiskImage
    if params.computeNodeCount > 1:
        iface = cpnode.addInterface("if0")
        mgmtlan.addInterface(iface)
        if generateIPs:
            iface.addAddress(rspec.IPv4Address(get_next_ipaddr(mgmtlan.client_id),
                                           get_netmask(mgmtlan.client_id)))
            pass
        pass
    cpnode.addService(rspec.Install(url=TBURL, path="/opt/"))
    if params.FluidMem and params.Infiniswap: 
      cpnode.addService(rspec.Execute(shell="sh",command=COMBINED_CMD))
    elif params.FluidMem: 
      cpnode.addService(rspec.Execute(shell="sh",command=FLUIDMEM_CMD))
    elif params.Infiniswap:
      cpnode.addService(rspec.Execute(shell="sh",command=INFINISWAP_CMD))
    else:
      cpnode.addService(rspec.Execute(shell="sh",command=BASE_CMD))
    request.addResource(cpnode)
    computeNodeList += cpname + ' '
    pass


#
# Add our parameters to the request so we can get their values to our nodes.
# The nodes download the manifest(s), and the setup scripts read the parameter
# values when they run.
#
class Parameters(rspec.Resource):
    def _write(self, root):
        ns = "{http://www.protogeni.net/resources/rspec/ext/johnsond/1}"
        paramXML = "%sparameter" % (ns,)
        
        el = ET.SubElement(root,"%sprofile_parameters" % (ns,))

        param = ET.SubElement(el,paramXML)
        param.text = 'COMPUTENODES="%s"' % (computeNodeList,)
        param.text = 'MGMTLAN="%s"' % (mgmtlan.client_id,)

        return el
    pass

parameters = Parameters()
request.addResource(parameters)

portal.context.printRequestRSpec()

