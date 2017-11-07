# XDFeatureDetection

This script is intended to detect the usage of key features within XenApp/XenDesktop sites.

## Getting Started

Simply execute the PowerShell script and output is returned on the feature usage.
From a powershell command prompt run the following

```powershell
./XDFeatureDetection_v105.ps1
```

## Prerequisites

Requires the built-in Citrix PowerShell snap-ins on the delivery controller

Must enable the running of 3rd party scripts within PowerShell (Set-ExecutionPolicy)

Must use an account that is both a local administrator and Citrix administrator

## Built With

* [Microsoft Powershell](https://msdn.microsoft.com/powershell)

## NEW IN THIS VERSION (1.0.5)

Initial release

## EXAMPLES

This script should be run (as administrator) on a delivery controller in a XenApp/XenDesktop site.

.\XDFeatureDetection_v105.ps1

## Versioning & Authors

VERSION
1.0.5

DATE MODIFIED
10/20/2017

AUTHOR
Allen Furmanski, Citrix Product Marketing
