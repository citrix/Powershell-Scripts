###################################
#######
#######
####### XA/XD Feature Detection
#######
####### Detects key features in
####### use within a site along
####### with entitlement info
#######
####### Version 1.1.0
#######
####### 11-30-2017
#######
#######
###################################

# Load Citrix snap-ins
asnp citrix*

# Get overall site configuration
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

# Check if XenDesktop is the product in use
function CheckXenDesktop ()
{
    if($siteConfig.ProductCode -ne 'XDT')
    {    
        return $false
    }
    else
    {
        return $true
    }

}


# Check if not using XD VDI Edition
function CheckNotVDIEdition ()
{
    if($siteConfig.ProductEdition -ne 'VDI')
    {    
        return $true
    }
    else
    {
        return $false
    }

}

# Check if eligible for platinum-level features
function CheckPlatinumFeature ()
{
    if($siteConfig.ProductEdition -ne 'PLT')
    {    
        return $false
    }
    else
    {
        return $true
    }

}

# Check if eligible for enterprise-level features and higher
function CheckEnterpriseFeature ()
{
    if(($siteConfig.ProductEdition -ne 'PLT')-and($siteConfig.ProductEdition -ne 'ENT'))
    {    
        return $false
    }
    else
    {
        return $true
    }

}

# Check if eligible for XD enterprise-level features and higher
function CheckXDEnterpriseFeature ()
{
    if(($siteConfig.Code -ne 'XDT')-and($siteConfig.ProductEdition -ne 'PLT')-and($siteConfig.ProductEdition -ne 'ENT'))
    {    
        return $false
    }
    else
    {
        return $true
    }

}

# Detect if delegated administration is in use
function CheckDelegatedAdmininUse ()
{
    $GetAdmins = Get-AdminAdministrator

    If ($GetAdmins.count -gt 1)
    {
        # Multiple administrator accounts exist
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

# Detect cloud connections in use
function CheckCloudConnectioninUse ()
{
    cd xdhyp:\connections
    $HostingConnections = dir

    # Only proceed if there are actual hosting connections
    If ($HostingConnections.count -gt 0)
    {
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
if($siteConfig.ProductCode -eq 'XDT')
{
    # XDT code is XenDesktop
    Write-Host "Product:`t XenDesktop"
}
else
{
    # Other code of MPS is XenApp
    Write-Host "Product:`t XenApp"
}
Write-Host "Edition:`t",$siteConfig.ProductEdition
Write-Host "Version:`t",$siteConfig.ProductVersion
Write-Host ""
Write-Host ""

Write-Host "Machine Creation Services (MCS)"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckMCSinUse)
Write-Host "Edition:`t`t`t All"
Write-Host "Entitled?:`t`t`t True"
Write-Host ""
Write-Host ""


Write-Host "Provisioning Services (PVS)"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckPVSinUse)
Write-Host "Edition:`t`t`t ENT,PLT"
Write-Host "Entitled?:`t`t`t",$(CheckEnterpriseFeature)
Write-Host ""
Write-Host ""


Write-Host "Delegated Administration"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckDelegatedAdmininUse)
Write-Host "Edition:`t`t`t ENT,PLT"
Write-Host "Entitled?:`t`t`t",$(CheckEnterpriseFeature)
Write-Host ""
Write-Host ""


Write-Host "Zones"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckZonesinUse)
Write-Host "Edition:`t`t`t All"
Write-Host "Entitled?:`t`t`t True"
Write-Host ""
Write-Host ""


Write-Host "Remote PC Access"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckRemotePCinUse)
Write-Host "Edition:`t`t`t XD ENT,PLT"
Write-Host "Entitled?:`t`t`t",$(CheckXDEnterpriseFeature)
Write-Host ""
Write-Host ""


Write-Host "Cloud Connections"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckCloudConnectioninUse)
Write-Host "Edition:`t`t`t ENT,PLT"
Write-Host "Entitled?:`t`t`t",$(CheckEnterpriseFeature)
Write-Host ""
Write-Host ""


Write-Host "SCOM Management Packs"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckSCOMPacksinUse)
Write-Host "Edition:`t`t`t PLT"
Write-Host "Entitled?:`t`t`t",$(CheckPlatinumFeature)
Write-Host ""
Write-Host ""


Write-Host "VDI Desktops"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckVDIinUse)
Write-Host "Edition:`t`t`t XD VDI,ENT,PLT"
Write-Host "Entitled?:`t`t`t",$(CheckXenDesktop)
Write-Host ""
Write-Host ""


Write-Host "Published Applications"
Write-Host "--------------------------------"
Write-Host "In Use?:`t`t`t",$(CheckAppsinUse)
Write-Host "Edition:`t`t`t All Except XD VDI"
Write-Host "Entitled?:`t`t`t",$(CheckNotVDIEdition)
Write-Host ""
Write-Host ""
