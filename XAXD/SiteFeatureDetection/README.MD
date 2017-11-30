# XDFeatureDetection

This script is intended to detect the usage of key features within XenApp/XenDesktop sites.

## Getting Started

Simply execute the PowerShell script and output is returned on the feature usage.
From a powershell command prompt run the following

```powershell
./XDFeatureDetection.ps1
```

## Prerequisites

Requires the built-in Citrix PowerShell snap-ins on the delivery controller

Must enable the running of 3rd party scripts within PowerShell (Set-ExecutionPolicy)

Must use an account that is both a local administrator and Citrix administrator

## Built With

* [Microsoft Powershell](https://msdn.microsoft.com/powershell)

## NEW IN THIS VERSION (1.1.0)

Cleaned up formatting, adjusted logic, now including feature eligibility

## EXAMPLES

This script should be run (as administrator) on a delivery controller in a XenApp/XenDesktop site.

.\XDFeatureDetection.ps1

## Versioning & Authors

VERSION
1.1.0

DATE MODIFIED
11/30/2017

AUTHOR
Allen Furmanski, Citrix Product Marketing
