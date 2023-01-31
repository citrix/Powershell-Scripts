# Get-ProvVmInUnknownPowerState

This script is to diagnose and (semi-) automatically resolve VMs on Citrix Virtual Apps and Desktops (CVAD) in an unknown power state. 


## Getting Started

Official documentation of this script is available here: https://info.citrite.net/x/84xlXg 

(This link is an internal blog link. This will be updated after public blog is published.)

## Context and Problems
The power state of the VMs on Citrix Virtual Apps and Desktops (CVAD) represents the power state of the corresponding VMs on hypervisors. However, in some cases, customers are experiencing VMs on CVAD continuously showing the power state unknown. Below are the reasons for the unknown power state. 

1. The ID of the VM on CVAD mismatches with the corresponding ID of the VM on the hypervisor.
2. The VM on the hypervisor is deleted.
3. The hypervisor connection on CVAD is broken.

The current practice to resolve the issue is helping the customers manually change the IDs of VM on CVAD stored on their database, change the IDs on the hypervisor, e.g., VMware, or delete and recreate the VMs. Those practices would be inconvenient and error-prone for customers, especially when a number of machines are in an unknown power state.


## A Solution: Get-ProvVmInUnknownPowerState

Get-ProvVmInUnknownPowerState diagnoses the VMs on CVAD in an unknown power state, reports the causes, and (semi-) automatically fixes the causes. Specifically, Get-ProvVmInUnknownPowerState utilizes the names of VMs on CVAD to find the corresponding VMs on hypervisors and check three scenarios below that can make the power state of the VMs unknown.

1. Scenario 1: the state of the hypervisor connection is unavailable. such as connection credentials being invalid.
2. Scenario 2: the VMs on the hypervisor are deleted.
3. Scenario 3: the IDs of VMs on CVAD mismatches the corresponding IDs of the VM on hypervisors. 

Get-ProvVmInUnknownPowerState can take a hypervisor connection name, a broker catalog name, and/or "-Fix" as input.

* If either a hypervisor connection name or a broker catalog is given, then Get-ProvVmInUnknownPowerState reports the VMs in an unknown power state associated with the hypervisor connection name or the broker catalog.
* If both a hypervisor connection name and a broker catalog are given, then Get-ProvVmInUnknownPowerState reports the VMs associated with the broker catalog, because the VMs on the catalog is a subset of the VMs on the hypervisor connection
* Without the "-Fix" parameter, the admin can get the report that includes the list of the VMs with the unknown power states together with the causes and suggestions.
* With the parameter "-Fix", the admin can get the report, and the script automatically resolved the issue of scenario 3 by updating the IDs of VMs. 

In case of scenario 1 and 2, Get-ProvVmInUnknownPowerState reports the causes of the unknown power state and provide suggestions to help admins fix the issues, such as correcting the credentials or deleting the VMs on CVAD. In the case of scenario 3, Get-ProvVmInUnknownPowerState reports the causes and suggestions. If the "-Fix" parameter is specified, Get-ProvVmInUnknownPowerState fixes the causes of scenario 3 automatically.

The scenario 1, 2, and 3 are exclusive. If the connection is unavailable, it is not possible to access the hypervisor; consequently, check whether the corresponding VM on the hypervisor is deleted or the IDs are matched.

## Prerequisites

Minimal permission to execute Set-BrokerMachine is required.


## Built With

* [Microsoft Powershell](https://msdn.microsoft.com/powershell)


## EXAMPLES

The detailed examples are described in the blog.


## Versioning & Authors

VERSION
1.0.1

CONTRIBUTORS

Haan Mo Johng, Engineering

Charlie Wang, Engineering
