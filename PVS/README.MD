# vDiskReplicator

This script is intended to replicate vDisks/versions from a Store accessible by the "export" PVS server to other PVS servers in the same Farm/Site and another Farm/Store/Site.

## Getting Started

All parameters ("export"/"import" servers, source/destination site, source/destination store, and disks to export) are either passed in or selected via the GUI.

All read-only vDisks/versions from a user-defined Store on the export PVS server are replicated to all other servers in a user-defined Site in the same Farm.

The same vDisks/versions are also replicated to a user-defined Store/Site (and all servers in that Site) in the same Farm as the import PVS server.

Script includes basic error handling, but assumes import and export PVS servers are unique.

Errors and information are written to the PowerShell host as well as the event log (Robocopy logs are also generated).

### Prerequisites

Must first run <Enable-WSManCredSSP -Role Server> on all PVS servers

Must first run <Enable-WSManCredSSP -Role Client -DelegateComputer "*.FULL.DOMAIN.NAME" -Force> on the PVS server this script is run from

Must first install PVS Console software on the PVS server this script is fun from

Must use an account that is a local administrator on all PVS servers

## Built With

* [Microsoft Powershell](https://msdn.microsoft.com/powershell)

## NEW IN THIS VERSION (2.0):

Bug Fixes -- fixed several bugs reported by the user community 

Intra-site Replication -- Running the script with the -INTRASITE switch (and required parameters -- see example below) will copy the .PVP, .VHD/X, and .AVHD/X files (including maintenance versions!) for each vDisk specified (or all vDisks on the server if the IS_vDisksToExport parameter is not used) from the IS_srcServer to all other PVS servers in the same site.

## EXAMPLES

This script should be run (as administrator) on a PVS server after any vDisk or vDisk version is promoted to production.

.\vDisk_Replicator_<Version>.ps1 -GUI

.\vDisk_Replicator_<Version>.ps1 -srcServer <FQDN> -srcSite <SITE> -srcStore <STORE> -dstServer <FQDN> -dstSite <SITE> -dstStore <STORE> [-vDisksToExport <ARRAY>]

.\vDisk_Replicator_<Version>.ps1 -INTRASITE -IS_srcServer <FQDN> [-IS_vDisksToExport <ARRAY>]

## Versioning & Authors

VERSION
2.0

DATE MODIFIED
6/19/2017

AUTHOR
Sam Breslow, Citrix Consulting