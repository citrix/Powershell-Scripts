# Autoscale Machine Creation Services

This script is intended to autoscale a delivery group based on load using
Machine Creation Services.

## Getting Started

Official documentation of this script is available here: https://docs.citrix.com/en-us/citrix-virtual-apps-desktops-service/manage-deployment/autoscale.html#dynamically-provision-machines-with-autoscale


A detailed description is also available within the script itself

```powershell
Get-Help .\Invoke-AutoscaleMachineCreation.ps1
```

## Prerequisites

Requires the Citrix Remote PowerShell SDK

Must enable the running of 3rd party scripts within PowerShell (Set-ExecutionPolicy)

Must use an account that is both a domain administator (or other user that is able to create machine accounts)

Other pre-requisites are detailed in the help text.

## Built With

* [Microsoft Powershell](https://msdn.microsoft.com/powershell)

## NEW IN THIS VERSION (1.0.1)

Ability to limit the maximum number of machines created by this script

## EXAMPLES

This script should be run from a machine that can access the Internet and is on the same
domain as the machines that will be created\added.

.\Invoke-AutoscaleMachineCreation.ps1 -DeliveryGroup <dg> -XdProfileName <profile>

## Versioning & Authors

VERSION
1.0.1

DATE MODIFIED
11/7/2019

AUTHOR
Cristopher Jimenez, Engineering