###################################
#######
#######
####### XA/XD Feature Detection
#######
####### Detects key features in
####### use within a site
#######
####### Version 1.0.5
#######
#######
###################################


asnp citrix*
$siteConfig = Get-ConfigSite


# Detect if MCS is in use
function CheckMCSinUse ()
{
    $GetBC = Get-BrokerCatalog
    $TotalMCS = ($GetBC.provisioningtype -eq 'MCS').count

    If ($TotalMCS -gt 0)
    {
        # One or more MCS catalogs were found so return true
        return $true
    }
    else
    {
        return $false
    }
}


# Detect if PVS is in use
function CheckPVSinUse ()
{
    $GetBC = Get-BrokerCatalog
    $TotalPVS = ($GetBC.provisioningtype -eq 'PVS').count

    If ($TotalPVS -gt 0)
    {
        # One or more PVS catalogs were found so return true
        return $true
    }
    else
    {
        return $false
    }
}

# Detect if delegated administration is in use
function CheckDelegatedAdmininUse ()
{
    $GetAdmins = Get-AdminAdministrator
    $DelegatedAdmins = ($GetAdmins.Rights -ne '{Full Administrator:All}').count

    If ($DelegatedAdmins -gt 0)
    {
        # One or more admins exist that are delegated without full admin permission
        return $true
    }
    else
    {
        return $false
    }
}

# Detect if zones are in use
function CheckZonesinUse ()
{
    $Zones = Get-ConfigZone
    
    If ($Zones.count -gt 1)
    {
        # More than one zone exists 
        return $true
    }
    else
    {
        return $false
    }
}

# Detect Remote PC Access in use
function CheckRemotePCinUse ()
{
    $GetBC = Get-BrokerCatalog
    $TotalRemotePC = ($GetBC.IsRemotePC -eq 'True').count

    If ($TotalRemotePC -gt 0)
    {
        # One or more Remote PC catalogs were found
        return $true
    }
    else
    {
        return $false
    }
}

# Detect cloud connection in use
function CheckCloudConnectioninUse ()
{
    cd xdhyp:\connections
    $HostingConnections = dir
    $TotalCloudConnections = ($HostingConnections.PluginId -eq 'AzureRmFactory').count + ($HostingConnections.PluginId -eq 'AWSMachineManagerFactory').count

    If ($TotalCloudConnections -gt 0)
    {
        # One or more cloud connections exist
        return $true
    }
    else
    {
        return $false
    }
}

# Detect SCOM Packs in use
function CheckSCOMPacksinUse ()
{

    # See if one or more Citrix SCOM components are installed on the controller
    if((Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName | where-object {$_.DisplayName -like 'Citrix SCOM*'} | measure | Select-Object -Exp Count) -gt 0)
    {
        return $true
    }
    else
    {
        return $false
    }

}

# Detect VDI in use
function CheckVDIinUse ()
{
    $GetBC = Get-BrokerCatalog
    $TotalVDI = ($GetBC.SessionSupport -eq 'SingleSession').count

    If ($TotalVDI -gt 0)
    {
        # One or more VDI catalogs found
        return $true
    }
    else
    {
        return $false
    }
}

# Check published apps in use
function CheckAppsinUse ()
{
    $GetApps = Get-BrokerApplication
    $TotalApps = $GetApps.count

    If ($TotalApps -gt 0)
    {
        # One or more published apps exist
        return $true
    }
    else
    {
        return $false
    }
}

# High-level site info
Write-Host "Site Name:`t",$siteConfig.SiteName
Write-Host "Product:`t",$siteConfig.ProductCode
Write-Host "Edition:`t",$siteConfig.ProductEdition
Write-Host "Version:`t",$siteConfig.ProductVersion
Write-Host ""

Write-Host "MCS in Use:`t",$(CheckMCSinUse)
Write-Host "PVS in Use:`t",$(CheckPVSinUse)
Write-Host ""

Write-Host "Delegated Admins in Use:`t",$(CheckDelegatedAdmininUse)
Write-Host "Zones in Use:`t`t`t`t",$(CheckZonesinUse)
Write-Host ""

Write-Host "Remote PC Access in Use:`t",$(CheckRemotePCinUse)
Write-Host "Cloud Connections in Use:`t",$(CheckCloudConnectioninUse)
Write-Host ""

Write-Host "SCOM Packs in Use:`t`t`t",$(CheckSCOMPacksinUse)
Write-Host "VDI in Use:`t`t`t`t`t",$(CheckVDIinUse)
Write-Host ""

Write-Host "Published Apps in Use:`t`t",$(CheckAppsinUse)