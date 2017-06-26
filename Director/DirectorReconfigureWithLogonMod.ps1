# /*************************************************************************
# *
# * THIS SAMPLE CODE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
# * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# *
# *************************************************************************/
<#
Script to configure director after an upgrade or just to make sure that all servers are 
configured the same. Also a great way to document the settings you want in your environment.
 
script also modifies the Logon.aspx file to pre-populate the domain field and 
show the windows server name on the logon page (for when you loadbalance the servers).
 
When run the script will copy the current configuration to a local folder for safekeeping.
Files are only written to the server if changes were made. 
#>
 
 
#Add configuration entires from the application config into the hashtable.
#Set the value to "delete" if you want it to be removed completely.
 
$AppKeys = @{}
$AppKeys["Service.AutoDiscoveryAddresses"]   = "Farm1Controller,Farm2Controller,Farm3Conroller"
$AppKeys["UI.EnableSslCheck"]                = "false"
$AppKeys["Service.AutoDiscoveryAddressesXA"] = "XAFarm1ZDC,XAFarm2ZDC"
 
#This will remove the ApplicationSetting completely from the Director configuration:
$AppKeys["Service.AutoDiscoveryAddressesXA"] = "delete"
 
#List all director servers to be configured
$directorServers = "Director1",
"Director2",
"Director3"
 
 
#Domain name to be shown in the domain field of the logon page.
#Does not support changing an existing value
$DomainName = "YOURDOMAIN"
 
#location where files will be copied before making any changes. Files are marked with source server and time stamp.
$LocalBackupFolder = "c:\temp"
 
$scriptTime = Get-Date
foreach ($server in $directorServers) {
    write-host $server
    #copy the current config files to some place local
    $webConfig = "\\$server\c$\inetpub\wwwroot\director\web.config"
    Copy-Item -Path $webConfig -Destination ($LocalBackupFolder+"\"+$scriptTime.ToString("yyyy-MM-dd_HHmm_")+$server+"_web.config")
    $LogonAsp  = "\\$server\c$\inetpub\wwwroot\director\LogOn.aspx"
    Copy-Item -Path $LogonAsp -Destination ($LocalBackupFolder+"\"+$scriptTime.ToString("yyyy-MM-dd_HHmm_")+$server+"_LogOn.aspx")
 
 
    #tracking file changes for web.config
    $FileChanges = $false
 
    $doc = (Get-Content $webConfig) -as [Xml]
    foreach ($key in $AppKeys.Keys) {
        $obj = $doc.configuration.appSettings.add | where {$_.Key -eq $key}
        if ($obj -eq $null -and $AppKeys[$key] -notlike "delete") {
            #Create a setting if it doesn't already exist (and is supposed to be there)
            $FileChanges = $true
            write-host "adding new config entry for $key"
            $newAppSetting = $doc.CreateElement("add")
            $doc.configuration.appSettings.AppendChild($newAppSetting) | Out-Null
            $newAppSetting.SetAttribute("key",$key);
            $newAppSetting.SetAttribute("value",$AppKeys[$key]);
        } elseif ($obj -ne $null -and $AppKeys[$key] -like "delete") {
            #Delete a setting if it's there and not supposed to be
            $FileChanges = $true
            write-host "removing config entry $key"
            $doc.configuration.appSettings.RemoveChild($obj) | Out-Null;   # Remove the desired module when found 
        } elseif ($obj -ne $null ) {
            #Update a setting if not already what it should be
            if($obj.value -notlike $AppKeys[$key]) {
                $FileChanges = $true
                write-host "Setting config entry for $key"
                $obj.value = $AppKeys[$key]
            }
        }
    }
    if ($FileChanges) { 
        write-host "Saving web.config"
        $doc.Save($webConfig) 
    }
 
 
    #tracking file changes for Logon.aspx
    $FileChanges = $false
 
    $text = gc $LogonAsp
    #Search the logon page for the entered domain name. If not found add a text field with the domain name
    if (($text | ? {$_ -imatch $DomainName} | measure).count -eq 0 -and $DomainName -ne "YOURDOMAIN") {
        $FileChanges = $true
        write-host "adding domain to logon page"
        $text = $text -replace 'ID="Domain"',('ID="Domain" text="'+$DomainName+'"')
    }
 
    #Search the logon page for the local machine name sting. If not found, add it in the footer.
    if (($text | ? {$_ -like "*String serverName = System.Environment.MachineName*"} | measure).count -eq 0) {
        $FileChanges = $true
        write-host "adding servername to logon page"
        $ReplaceWith = 'Citrix Systems, Inc.</a>
<% String serverName = System.Environment.MachineName; %>
<p style="font-size: 70%; margin: -14px; padding: 0px; color: #555555;text-align: center;" id="serverid"><%=serverName %></p>'
        $text = $text -ireplace "Citrix Systems, Inc.</a>",$ReplaceWith
    }
    if ($FileChanges) {
        write-host "saving Logon.aspx"
        $text | Out-File $LogonAsp -Encoding utf8
    }
}
