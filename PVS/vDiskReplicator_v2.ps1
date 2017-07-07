<#
    .SYNOPSIS
        vDisk Replicator Script

    .DESCRIPTION
        This script is intended to replicate vDisks/versions from a Store accessible by the "export" PVS server to other PVS servers in the same Farm/Site and another Farm/Store/Site.
        All parameters ("export"/"import" servers, source/destination site, source/destination store, and disks to export) are either passed in or selected via the GUI.
        All read-only vDisks/versions from a user-defined Store on the export PVS server are replicated to all other servers in a user-defined Site in the same Farm.
        The same vDisks/versions are also replicated to a user-defined Store/Site (and all servers in that Site) in the same Farm as the import PVS server.
        Script includes basic error handling, but assumes import and export PVS servers are unique.
        Errors and information are written to the PowerShell host as well as the event log (Robocopy logs are also generated).
        Must first run <Enable-WSManCredSSP -Role Server> on all PVS servers
        Must first run <Enable-WSManCredSSP -Role Client -DelegateComputer "*.FULL.DOMAIN.NAME" -Force> on the PVS server this script is run from
        Must first install PVS Console software on the PVS server this script is fun from
        Must use an account that is a local administrator on all PVS servers

        NEW in this version (2.0):
        Bug Fixes -- fixed several bugs reported by the user community 
        Intra-site Replication -- Running the script with the -INTRASITE switch (and required parameters -- see example below) will copy the .PVP, .VHD/X, and .AVHD/X files
        (including maintenance versions!) for each vDisk specified (or all vDisks on the server if the IS_vDisksToExport parameter is not used) from the IS_srcServer to all other 
        PVS servers in the same site.

    .EXAMPLE
        This script should be run (as administrator) on a PVS server after any vDisk or vDisk version is promoted to production.
        .\vDisk_Replicator_<Version>.ps1 -GUI
        .\vDisk_Replicator_<Version>.ps1 -srcServer <FQDN> -srcSite <SITE> -srcStore <STORE> -dstServer <FQDN> -dstSite <SITE> -dstStore <STORE> [-vDisksToExport <ARRAY>]
        .\vDisk_Replicator_<Version>.ps1 -INTRASITE -IS_srcServer <FQDN> [-IS_vDisksToExport <ARRAY>]

    .VERSION
        2.0

    .DATE MODIFIED
        6/19/2017

    .AUTHOR
        Sam Breslow, Citrix Consulting
#>

# /***************************************************************************************
# *
# * This software / sample code is provided to you “AS IS” with no representations, 
# * warranties or conditions of any kind. You may use, modify and distribute it at 
# * your own risk. CITRIX DISCLAIMS ALL WARRANTIES WHATSOEVER, EXPRESS, IMPLIED, 
# * WRITTEN, ORAL OR STATUTORY, INCLUDING WITHOUT LIMITATION WARRANTIES OF 
# * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NONINFRINGEMENT. 
# * Without limiting the generality of the foregoing, you acknowledge and agree that 
# * (a) the software / sample code may exhibit errors, design flaws or other problems, 
# * possibly resulting in loss of data or damage to property; (b) it may not be 
# * possible to make the software / sample code fully functional; and (c) Citrix may, 
# * without notice or liability to you, cease to make available the current version 
# * and/or any future versions of the software / sample code. In no event should the 
# * software / sample code be used to support of ultra-hazardous activities, including 
# * but not limited to life support or blasting activities. NEITHER CITRIX NOR ITS 
# * AFFILIATES OR AGENTS WILL BE LIABLE, UNDER BREACH OF CONTRACT OR ANY OTHER THEORY 
# * OF LIABILITY, FOR ANY DAMAGES WHATSOEVER ARISING FROM USE OF THE SOFTWARE / SAMPLE 
# * CODE, INCLUDING WITHOUT LIMITATION DIRECT, SPECIAL, INCIDENTAL, PUNITIVE, 
# * CONSEQUENTIAL OR OTHER DAMAGES, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. 
# * Although the copyright in the software / sample code belongs to Citrix, any 
# * distribution of the code should include only your own standard copyright attribution,
# * and not that of Citrix. You agree to indemnify and defend Citrix against any and 
# * all claims arising from your use, modification or distribution of the code.
# *
# ***************************************************************************************/


#Define Parameters
Param(
    [Parameter(ParameterSetName="GUI",Mandatory=$true)][switch]$gui,
    [Parameter(ParameterSetName="INTRASITE",Mandatory=$true)][switch]$INTRASITE,
    [Parameter(ParameterSetName="INTRASITE",Mandatory=$true)][string]$IS_srcServer,
    [Parameter(ParameterSetName="INTRASITE",Mandatory=$false)][array]$IS_vDisksToExport,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$srcServer,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$srcSite,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$srcStore,
    [Parameter(ParameterSetName="CLI",Mandatory=$false)][array]$vDisksToExport,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$dstServer,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$dstSite,
    [Parameter(ParameterSetName="CLI",Mandatory=$true)][string]$dstStore
)

#Check for Administrator rights
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)){
    Write-Host “You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!” -BackgroundColor Black -ForegroundColor Red
    Exit
}

#Initialize Event Log source
$replication = "vDisk Replicator Script"
try{
    $check = ([System.Diagnostics.EventLog]::SourceExists($replication))
    if (!$check){
        New-EventLog -LogName Application -Source $replication
    }
    $msg = "vDiskReplicator Script Initialized."
    Write-EventLog -LogName Application -Source $replication -EventId 1 -EntryType Information -Message $msg -Category 0
}
catch{
    Write-Host $_.Exception.GetType().FullName -BackgroundColor Black -ForegroundColor Red
}

#General Trap for unhandled errors
trap {
    Write-Host “GENERAL ERROR, SEE EVENT LOG” -BackgroundColor Black -ForegroundColor Red
    $msg = "GENERAL ERROR: "+$_.Exception
    Write-EventLog -LogName Application -Source $replication -EventId 0 -EntryType Error -Message $msg -Category 0
}

#Import PVS PowerShell Module
try{
    Import-Module 'C:\Program Files\Citrix\Provisioning Services console\Citrix.PVS.SnapIn.dll' -ErrorAction Stop
} 
catch {
    Write-Host "PVS PowerShell Snap-In Not Found" -BackgroundColor Black -ForegroundColor Red
    $msg = "PVS PowerShell Snap-In Not Found on $env:computername.  Script terminated."
    Write-EventLog -LogName Application -Source $replication -EventId 2 -EntryType Error -Message $msg -Category 0
    exit
}

#Define Functions
function Create-Form($size){
    $Form = New-Object System.Windows.Forms.Form
    $Form.Size = $size
    $Icon = [System.Drawing.Icon]::ExtractAssociatedIcon("C:\Program Files\Citrix\Provisioning Services Console\Console.msc")
    $form.Icon = $icon
    $form.Text = "vDisk Replicator Setup"
    $form.FormBorderStyle = 'FixedDialog' #MZ - Don't use fixed dialog, especially if you expect long paths
    $Form.Add_Shown({$Form.Activate()})
    return $Form
}

function Validate-Servers($srcServer, $dstServer){
    $msg = ""
    $exportMsg = ""
    $importMsg = ""
    try{
        Set-PvsConnection -Server $srcServer -Port 54321 -ErrorAction Stop | Out-Null
    } catch {
        $exportMsg = "Invalid Export Server: $srcServer"
    }
    try{
        Set-PvsConnection -Server $dstServer -Port 54321 -ErrorAction Stop | Out-Null
    } catch {
        $importMsg = "Invalid Import Server: $dstServer"
    }
    if($exportMsg -like ""){
        $msg = $importMsg
    } else {
        $msg = "$exportMsg, $importMsg"
    }
    return $msg
}

function Validate-SitesAndStores($server, $site, $store){
    $msg = ""
    try{
        Set-PvsConnection -Server $server -Port 54321 -ErrorAction Stop | Out-Null
    } catch {
        $msg = "Invalid Server: $server."
        exit
    }
    $siteExists = $true
    try{
        Get-PvsSite -SiteName $site | Out-Null
    } catch {
        $siteExists = $false
    }
    $storeExists = $true
    try{
        Get-PvsStore -StoreName $store | Out-Null
    } catch{
        $storeExists = $false
    }
    if(!$siteExists){
        $msg += "  Invalid SERVER -> SITE combination: $server -> $site."
    }
    if(!$storeExists){
        $msg += "  Invalid SERVER -> STORE combination: $server -> $store."
    }
    return $msg
}

function Validate-ExportList($server, $list){
    $msg = ""
    try{
        Set-PvsConnection -Server $server -Port 54321 -ErrorAction Stop | Out-Null
    } catch {
        $msg = "Invalid Server: $server."
        exit
    }
    if($list.Length -ne 0){
        $invalidDisks = ""
        $realDisks = Get-PvsDiskLocator | select-object -expandProperty DiskLocatorName
        $comparison = Compare-Object -ReferenceObject $realDisks -DifferenceObject $list
        foreach($c in $comparison){
            if($c.SideIndicator -like "=>"){
                $invalidDisks += $c.InputObject
            }
        }
        if($invalidDisks.Length -ne 0){
            $invalidDisks = $invalidDisks.TrimEnd(", ")
            $msg += "The following vDisk names are invalid: $invalidDisks"
            if($invalidDisks.Length -eq $list.Length){
                $msg +="`nThe ExportList must contain at least one valid vDisk."
                exit
            }
        }
    } else {
        $msg = "The ExportList must contain at least one vDisk."
    }
    return $msg
}

function Start-Robocopy($server, $srcPath, $dstPath, $disk, $cred, $eventLog){ 
    $fqdn = $server.serverFQDN
    $msg = "Begining Robocopy procedure for $disk on $fqdn"
    Write-EventLog -LogName Application -Source $eventLog -EventId 9 -EntryType Information -Message $msg -Category 0
    Invoke-Command -ComputerName $fqdn -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.vhd" /MT 8 "/log:C:\vhdRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.VHD replication"
    Invoke-Command -ComputerName $fqdn -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.vhdx" /MT 8 "/log:C:\vhdxRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.VHDX replication"
    Invoke-Command -ComputerName $fqdn -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.avhd" /MT 8 "/log:C:\avhdRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.AVHD replication"
    Invoke-Command -ComputerName $fqdn -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.avhdx" /MT 8 "/log:C:\avhdxRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.AVHDx replication"
    Invoke-Command -ComputerName $fqdn -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.pvp" /MT 8 "/log:C:\pvpRepLog_$d" /v /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.PVP replication"
    if(!$server.sameFarm){
        Invoke-Command -ComputerName $fqdn -ScriptBlock {
            $d = $args[2]
            robocopy  $args[0] $args[1] /np /xo /J "$d*.xml" /MT 8 "/log:C:\xmlRepLog_$d" /v /b /R:5 /W:5
        } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.XML replication"
    }
    invoke-command -ComputerName $fqdn -scriptblock{
        $processes = Get-WmiObject -Class win32_process -Filter "name='robocopy.exe'"
        foreach($p in $processes){
            $p.setPriority(128)
        }
    } -Authentication Credssp -Credential $cred -AsJob -JobName "RoboCopy Process Priority"
}

function Start-ISRobocopy($server, $srcPath, $dstPath, $disk, $cred, $eventLog){
    $msg = "Begining Robocopy procedure for $disk on $server"
    Write-EventLog -LogName Application -Source $eventLog -EventId 9 -EntryType Information -Message $msg -Category 0
    Invoke-Command -ComputerName $server -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.vhd" /MT 8 "/log:C:\vhdRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.VHD replication"
    Invoke-Command -ComputerName $server -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.vhdx" /MT 8 "/log:C:\vhdxRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.VHDX replication"
    Invoke-Command -ComputerName $server -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.avhd" /MT 8 "/log:C:\avhdRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.AVHD replication"
    Invoke-Command -ComputerName $server -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.avhdx" /MT 8 "/log:C:\avhdxRepLog_$d" /v /b /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.AVHDx replication"
    Invoke-Command -ComputerName $server -ScriptBlock {
        $d = $args[2]
        robocopy  $args[0] $args[1] /np /xo /J "$d*.pvp" /MT 8 "/log:C:\pvpRepLog_$d" /v /R:5 /W:5
    } -ArgumentList $srcPath, $dstPath, $disk -Credential $cred -Authentication Credssp -AsJob -JobName "$disk.PVP replication"
    invoke-command -ComputerName $server -scriptblock{
        $processes = Get-WmiObject -Class win32_process -Filter "name='robocopy.exe'"
        foreach($p in $processes){
            $p.setPriority(128)
        }
    } -Authentication Credssp -Credential $cred -AsJob -JobName "RoboCopy Process Priority"
}

function Start-Replication($cred, $srcServer, $srcSite, $srcStore, $vDisksToExport, $dstServer, $dstSite, $dstStore, $eventLog){
    #Begin Export Prerequisites
    $destinationServers = @()
    Set-PvsConnection -Server $srcServer -Port 54321 | Out-Null
    foreach($s in (Get-PvsServer -SiteName $srcSite | Select-Object -ExpandProperty ServerFQDN)){
        if($s -notlike $srcServer){
            $serverObj = New-Object -TypeName PSObject -Property (@{'ServerFQDN'=$s;'sameFarm'=$true})
            $destinationServers += $serverObj
        }
    }
    foreach($d in $vDisksToExport){
        try{
            $disk = Get-PvsDiskLocator -DiskLocatorName $d -StoreName $srcStore -SiteName $srcSite
            Export-PvsDisk -DiskLocatorId $disk.DiskLocatorId
            Write-Host "Exporting vDisk"$disk.Name
            $msg = "Exporting vDisk: "+$disk.Name
            Write-EventLog -LogName Application -Source $eventLog -EventId 7 -EntryType Information -Message $msg -Category 0
        } catch {
            Write-Host "Could not export"$_.Exception -BackgroundColor Black -ForegroundColor Red
            $msg = "Could not export "+$_.Exception
            Write-EventLog -LogName Application -Source $eventLog -EventId 8 -EntryType Error -Message $msg -Category 0
            $vDisksToExport = $vDisksToExport -ne $disk.name
        }
    }
    $srcStorePath = Get-PvsStore -StoreName $srcStore | Select-Object -ExpandProperty Path
    Set-PvsConnection -Server $dstServer -Port 54321 | Out-Null
    foreach($s in (Get-PvsServer -SiteName $dstSite | Select-Object -ExpandProperty ServerFQDN)){
        $serverObj = New-Object -TypeName PSObject -Property (@{'ServerFQDN'=$s;'sameFarm'=$false})
        $destinationServers += $serverObj
    }
    $dstStorePath = Get-PvsStore -StoreName $dstStore | Select-Object -ExpandProperty Path
    #Begin Robocopy
    $srcStorePath = $srcStorePath -replace ':','$'
    $srcPath = "\\$srcServer\$srcStorePath"
    $dstStorePath = $dstStorePath -replace ':','$'
    foreach($ds in $destinationServers){
        $dsFQDN = $ds.ServerFQDN
        $dstPath = "\\$dsFQDN\$dstStorePath"
        foreach($vdisk in $vDisksToExport){
            Write-host "CALLING ROBOCOPY"
            if($ds.sameFarm){
                Start-Robocopy -server $ds -srcPath $srcPath -dstPath "\\$dsFQDN\$srcStorePath" -disk $vdisk -cred $cred -eventLog $eventLog
            } else {
                Start-Robocopy -server $ds -srcPath $srcPath -dstPath $dstPath -disk $vdisk -cred $cred -eventLog $eventLog
            }
        }
    }
    #Wait for all Robocopy processes to complete before attempting to import/add vDisks/versions
    Wait-Job -State Running
    #Begin Import
    #Gather Destination Farm vDisks/versions to determine if exported vDisks/versions need to be imported or added
    $dstDisks = Get-PvsDiskLocator -SiteName $dstSite
    foreach($vdisk in $vDisksToExport){
        foreach($d in $dstDisks){
            if($vdisk -like $d.Name){
                try{
                    Add-PvsDiskVersion -StoreName $dstStore -SiteName $dstSite -Name $vdisk
                } catch {
                    Write-host "Could not import vDisk versions for"$_.Exception -BackgroundColor Black -ForegroundColor Red
                    $msg = "Could not import vDisk versions for "+$_.Exception
                    Write-EventLog -LogName Application -Source $eventLog -EventId 10 -EntryType Error -Message $msg -Category 0
                }
                break;
            }
        }
        if(Test-Path "\\$dstserver\$dststorepath\$vdisk*.vhdx"){
            Write-Host "VHDX IMPORT"
            try{
                Import-PvsDisk -StoreName $dstStore -SiteName $dstSite -Name $vdisk -VHDX
            } catch {
                Write-host "Could not import vDisk for"$_.Exception -BackgroundColor Black -ForegroundColor Red
                $msg = "Could not import vDisk for "+$_.Exception
                Write-EventLog -LogName Application -Source $eventLog -EventId 11 -EntryType Error -Message $msg -Category 0
            }
        } else {
            Write-Host "VHD IMPORT"
            try{
                Import-PvsDisk -StoreName $dstStore -SiteName $dstSite -Name $vdisk
            } catch {
                Write-host "Could not import vDisk for"$_.Exception -BackgroundColor Black -ForegroundColor Red
                $msg = "Could not import vDisk for "+$_.Exception
                Write-EventLog -LogName Application -Source $eventLog -EventId 11 -EntryType Error -Message $msg -Category 0
            }
        }
    }
}

function out-cli($srcServer, $srcSite, $srcStore, $vDisksToExport, $dstServer, $dstSite, $dstStore){
    $outpath = pwd
    $outpath = $outpath.Path
    $line = '$srcServer = '+"'$srcServer'"
    $line > "$outpath\vDiskReplicatorCLI.ps1"
    $line = '$srcSite = '+"'$srcSite'"
    $line >> "$outpath\vDiskReplicatorCLI.ps1"
    $line = '$srcStore = '+"'$srcStore'"
    $line >> "$outpath\vDiskReplicatorCLI.ps1"

    $line = '$dstServer = '+"'$dstServer'"
    $line >> "$outpath\vDiskReplicatorCLI.ps1"
    $line = '$dstSite = '+"'$dstSite'"
    $line >> "$outpath\vDiskReplicatorCLI.ps1"
    $line = '$dstStore = '+"'$dstStore'"
    $line >> "$outpath\vDiskReplicatorCLI.ps1"

    $line = '$vDisksToExport = @()'
    $line >> "$outpath\vDiskReplicatorCLI.ps1"
    foreach($disk in $vDisksToExport){
        $line = '$vDisksToExport += '+"'$disk'"
        $line >> "$outpath\vDiskReplicatorCLI.ps1"
    }

    $line = '.\vDiskReplicator.ps1 -srcServer $srcServer -srcSite $srcSite -srcStore $srcStore -dstServer $dstServer -dstSite $dstSite -dstStore $dstStore -vDisksToExport $vDisksToExport'
    $line >> "$outpath\vDiskReplicatorCLI.ps1"
}

### START SCRIPT

if($INTRASITE){
    $msg = Validate-Servers -srcServer $IS_srcServer -dstServer $IS_srcServer
    if($msg -notlike ""){
        Write-Host $msg -BackgroundColor Black -ForegroundColor Red
        $msg += ".  Script Terminated."
        Write-EventLog -LogName Application -Source $replication -EventId 3 -EntryType Error -Message $msg -Category 0
        exit
    }
    Set-PvsConnection -Server $IS_srcServer -Port 54321 -ErrorAction Stop | Out-Null
    $IS_srvObj = Get-PvsServer -ServerName $IS_srcServer.Split('.')[0]
    $IS_site = Get-PvsSite -SiteName $IS_srvObj.SiteName
    $IS_storeID = (Get-PvsServerStore -ServerName $IS_srcServer.Split('.')[0]).StoreID.ToString()
    $IS_storePath = (Get-PvsStore -StoreId $IS_storeID).Path
    $IS_dstServers = @()
    foreach($s in (Get-PvsServer -SiteName $IS_site.SiteName | Select-Object -ExpandProperty ServerFQDN)){
        if($s -notlike $IS_srcServer){
            $IS_dstServers += $s
        }
    }
    ##CHECK VDISKS
    if($vDisksToExport.Length -ne 0){
        $exportMsg = Validate-ExportList -server $srcServer -list $vDisksToExport
        if($exportMsg -notlike ""){
                Write-Host $exportMSG -BackgroundColor Black -ForegroundColor Red
                $exportMsg += ".  Script Terminated."
                Write-EventLog -LogName Application -Source $replication -EventId 5 -EntryType Error -Message $exportMsg -Category 0
                exit
        }
    }
    else{
        $exportMsg = "No list of vDisks to export found.  Exporting ALL vDisks found on $IS_srcServer."
        Write-EventLog -LogName Application -Source $replication -EventId 6 -EntryType Warning -Message $exportMsg -Category 0
        $IS_vDisksToExport = Get-PvsDiskLocator -StoreID $IS_StoreID -SiteName $IS_Site.SiteName | Select-Object -ExpandProperty DiskLocatorName
    }
    $IS_StorePath = $IS_StorePath -replace ':','$'
    $IS_srcPath = "\\$IS_srcServer\$IS_StorePath"
    $cred = Get-Credential
    foreach($s in $IS_dstServers){
        $IS_dstPath = "\\$s\$IS_StorePath"
        foreach($vdisk in $IS_vDisksToExport){
            Start-ISRobocopy -server $s -srcPath $IS_srcPath -dstPath $IS_dstPath -disk $vdisk -cred $cred -eventLog $replication
        }
    }
    Wait-Job -State Running
    Write-Host DONE
}elseif($gui){
    #Load GUI modules
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $Form = Create-Form(New-Object System.Drawing.Size(500,220))
    $Form.Text += " (1 of 3)"
    $srcFarmLabel = New-Object System.Windows.Forms.Label
    $srcFarmLabel.Text = "Enter Export PVS Server FQDN:"
    $srcFarmLabel.AutoSize = $true
    $srcFarmLabel.Location = New-Object System.Drawing.Size(0,15)
    $form.Controls.Add($srcFarmLabel)
    $srcFarmTextBox = New-Object System.Windows.Forms.textBox
    $srcFarmTextBox.Location = New-Object System.Drawing.Size(5,45)
    $srcFarmTextBox.Size = New-Object System.Drawing.Size(300,20)
    $srcFarmTextBox.Text = ""
    $Form.Controls.Add($srcFarmTextBox)

    $dstFarmLabel = New-Object System.Windows.Forms.Label
    $dstFarmLabel.Text = "Enter Import PVS Server FQDN:"
    $dstFarmLabel.AutoSize = $true
    $dstFarmLabel.Location = New-Object System.Drawing.Size(0,75)
    $form.Controls.Add($dstFarmLabel)
    $dstFarmTextBox = New-Object System.Windows.Forms.textBox
    $dstFarmTextBox.Location = New-Object System.Drawing.Size(5,105)
    $dstFarmTextBox.Size = New-Object System.Drawing.Size(300,20)
    $dstFarmTextBox.Text = ""
    $Form.Controls.Add($dstFarmTextBox)

    $outputBox = New-Object System.Windows.Forms.Label
    $outputBox.Location = New-Object System.Drawing.Size(5,150)
    $outputBox.Size = New-Object System.Drawing.Size(460,20)
    $Form.Controls.Add($outputBox)

    $Button = New-Object System.Windows.Forms.Button
    $Button.Location = New-Object System.Drawing.Size(350,30)
    $Button.Size = New-Object System.Drawing.Size(110,80)
    $Button.Text = "Next"
    $Button.Add_Click({
        $srcServer = $srcFarmTextBox.Text
        $dstServer = $dstFarmTextBox.Text
        $msg = Validate-Servers -srcServer $srcServer -dstServer $dstServer
        #$msg = "" #REMOVE THIS -- FOR TESTING ONLY
        if($msg -like ""){
            $Form.Close() | Out-Null
            $Form = Create-Form(New-Object System.Drawing.Size(500,220))
            $Form.Text += " (2 of 3)"
            #Create Source Store Drop Down Box
            $srcStoreLabel = New-Object System.Windows.Forms.Label
            $srcStoreLabel.Text = "Select Source Store:"
            $srcStoreLabel.AutoSize = $true
            $srcStoreLabel.Location = New-Object System.Drawing.Size(0,15)
            $form.Controls.Add($srcStoreLabel)
            $srcStoreDropDownBox = New-Object System.Windows.Forms.ComboBox
            $srcStoreDropDownBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
            $srcStoreDropDownBox.Location = New-Object System.Drawing.Size(130,10)
            $srcStoreDropDownBox.Size = New-Object System.Drawing.Size(200,20)
            $srcStoreDropDownBox.DropDownHeight = 200
            $Form.Controls.Add($srcStoreDropDownBox)
            Set-PvsConnection -Server $srcServer -Port 54321
            $srcStores = Get-PvsStore
            foreach ($s in $srcStores){
                $srcStoreDropDownBox.Items.Add($s.StoreName) | Out-Null
            }
            #Create Source Site Drop Down Box
            $srcSiteLabel = New-Object System.Windows.Forms.Label
            $srcSiteLabel.Text = "Select Source Site:"
            $srcSiteLabel.AutoSize = $true
            $srcSiteLabel.Location = New-Object System.Drawing.Size(0,45)
            $form.Controls.Add($srcSiteLabel)
            $srcSiteDropDownBox = New-Object System.Windows.Forms.ComboBox
            $srcSiteDropDownBox.Location = New-Object System.Drawing.Size(130,40)
            $srcSiteDropDownBox.Size = New-Object System.Drawing.Size(200,20)
            $srcSiteDropDownBox.DropDownHeight = 200
            $Form.Controls.Add($srcSiteDropDownBox)
            $srcSites = Get-PvsSite
            foreach ($s in $srcSites){
                $srcSiteDropDownBox.Items.Add($s.SiteName) | Out-Null
            }
            #Create Destination Store Drop Down Box
            $dstStoreLabel = New-Object System.Windows.Forms.Label
            $dstStoreLabel.Text = "Select Destination Store:"
            $dstStoreLabel.AutoSize = $true
            $dstStoreLabel.Location = New-Object System.Drawing.Size(0,75)
            $form.Controls.Add($dstStoreLabel)
            $dstStoreDropDownBox = New-Object System.Windows.Forms.ComboBox
            $dstStoreDropDownBox.Location = New-Object System.Drawing.Size(130,70)
            $dstStoreDropDownBox.Size = New-Object System.Drawing.Size(200,20)
            $dstStoreDropDownBox.DropDownHeight = 200
            $Form.Controls.Add($dstStoreDropDownBox)
            Set-PvsConnection -Server $dstServer -Port 54321
            $dstStores = Get-PvsStore
            foreach ($d in $dstStores){
                $dstStoreDropDownBox.Items.Add($d.StoreName) | Out-Null
            }
            #Create Destination Site Drop Down Box
            $dstSiteLabel = New-Object System.Windows.Forms.Label
            $dstSiteLabel.Text = "Select Destination Site:"
            $dstSiteLabel.AutoSize = $true
            $dstSiteLabel.Location = New-Object System.Drawing.Size(0,105)
            $form.Controls.Add($dstSiteLabel)
            $dstSiteDropDownBox = New-Object System.Windows.Forms.ComboBox
            $dstSiteDropDownBox.Location = New-Object System.Drawing.Size(130,100)
            $dstSiteDropDownBox.Size = New-Object System.Drawing.Size(200,20)
            $dstSiteDropDownBox.DropDownHeight = 200
            $Form.Controls.Add($dstSiteDropDownBox)
            $dstSites = Get-PvsSite
            foreach ($d in $dstSites){
                $dstSiteDropDownBox.Items.Add($d.SiteName) | Out-Null
            }
            #Add Output Box to Form
            $outputBox = New-Object System.Windows.Forms.Label
            $outputBox.Location = New-Object System.Drawing.Size(10,150)
            $outputBox.Size = New-Object System.Drawing.Size(460,20)
            $Form.Controls.Add($outputBox)
            #Add "Select" Button to Form
            $Button = New-Object System.Windows.Forms.Button
            $Button.Location = New-Object System.Drawing.Size(350,30)
            $Button.Size = New-Object System.Drawing.Size(110,80)
            $Button.Text = "Select"
            $Button.Add_Click({
                $srcStore = $srcStoreDropDownBox.SelectedItem
                $srcSite = $srcSiteDropDownBox.SelectedItem
                $dstStore = $dstStoreDropDownBox.SelectedItem
                $dstSite = $dstSiteDropDownBox.SelectedItem
                if(($srcStore -ne $null) -and ($srcSite -ne $null) -and ($dstStore -ne $null) -and ($dstSite -ne $null)){
                    $Form.Close() | Out-Null
                    $Form = Create-Form(New-Object System.Drawing.Size(500,220))
                    $Form.Text += " (3 of 3)"
                    $cbLabel = New-Object System.Windows.Forms.Label
                    $cbLabel.Text = "Select vDisks to export:"
                    $cbLabel.AutoSize = $true
                    $cbLabel.Location = New-Object System.Drawing.Size(10,10)
                    $form.Controls.Add($cbLabel)

                    Set-PvsConnection -Server $srcServer -Port 54321
                    $disks = Get-PvsDiskLocator -StoreName $srcStore -SiteName $srcSite
                    $checkBoxes = @()
                    $counter = 0
                    foreach($d in $disks){
                        $cb = new-object System.Windows.Forms.checkbox
                        $cb.Size = new-object System.Drawing.Size(250,50)
                        $y = 30+(35*$counter)
                        $cb.Location = new-object System.Drawing.Size(10,$y)
                        $cb.Text = $d.disklocatorname
                        $cb.Checked = $true
                        $checkBoxes += $cb
                        $Form.Controls.Add($cb)
                        $counter += 1
                    }
                    $y+=110+70
                    $Form.Size = New-Object System.Drawing.Size(500,$y)
                    $newY = $y
                   
                    #Add Output Box to Form
                    $y-=60
                    $cbOutputBox = New-Object System.Windows.Forms.Label
                    $cbOutputBox.Location = New-Object System.Drawing.Size(10,$y)
                    $cbOutputBox.Size = New-Object System.Drawing.Size(460,20)
                    $Form.Controls.Add($cbOutputBox)

                    $y-=50
                    $cbButton = New-Object System.Windows.Forms.Button
                    $cbButton.Location = New-Object System.Drawing.Size(350,30)
                    $cbButton.Size = New-Object System.Drawing.Size(110,$y)
                    $cbButton.Text = "Start"
                    $cbButton.Add_Click({
                        $vDisksToExport = @() 
                        foreach($i in $checkBoxes){
                            if($i.Checked){
                                $vDisksToExport += $i.Text
                            }
                        }
                        if($vDisksToExport.length -eq 0){
                            $cbOutputBox.Text = "Select at least one vDisk"
                        } else{
                            $cred = Get-Credential DOMAIN\USER
                            START-REPLICATION -cred $cred -srcServer $srcServer -srcSite $srcSite -srcStore $srcStore -vDisksToExport $vDisksToExport -dstServer $dstServer -dstSite $dstSite -dstStore $dstStore -eventLog $replication
                            $Form.close() | Out-Null
                            $finalmsg = "vDisk Replication Script Complete."
                            Write-EventLog -LogName Application -Source $replication -EventId 11 -EntryType Information -Message $finalmsg -Category 0
                        }
                    })
                    
                    $y=$cbOutputBox.Location.Y+$cboutputbox.Size.Height+20 
                    $txtButton = New-Object System.Windows.Forms.Button
                    $txtButton.Location = New-Object System.Drawing.Size(350,$y)
                    $txtButton.Size = New-Object System.Drawing.Size(110,30)
                    $txtbutton.Text = "Output CLI"
                    $txtButton.Add_click({
                        $vDisksToExport = @() 
                        foreach($i in $checkBoxes){
                            if($i.Checked){
                                $vDisksToExport += $i.Text
                            }
                        }
                        if($vDisksToExport.length -eq 0){
                            $cbOutputBox.Text = "Select at least one vDisk"
                        } else{
                            out-cli -srcServer $srcServer -srcSite $srcSite -srcStore $srcStore -vDisksToExport $vDisksToExport -dstServer $dstServer -dstSite $dstSite -dstStore $dstStore
                        }
                    })
                    $newy+=50
                    $Form.Size = New-Object System.Drawing.Size(500,$newy)

                    $form.Controls.Add($cbButton)
                    $form.Controls.Add($txtButton)
                    $form.showDialog()
                } else {
                    $outputBox.Text="Select a Valid Option"
                }
            })
            $Form.Controls.Add($Button)
            $Form.showDialog()
        } else{
            $outputBox.Text = $msg
        }
    })
    $Form.Controls.Add($Button)
    $Form.showDialog()
}
else {
    $msg = Validate-Servers -srcServer $srcServer -dstServer $dstServer
    if($msg -notlike ""){
        Write-Host $msg -BackgroundColor Black -ForegroundColor Red
        $msg += ".  Script Terminated."
        Write-EventLog -LogName Application -Source $replication -EventId 3 -EntryType Error -Message $msg -Category 0
        exit
    }
    $srcMsg = Validate-SitesAndStores -server $srcServer -site $srcSite -store $srcStore
    $dstMsg = Validate-SitesAndStores -server $dstServer -site $dstSite -store $dstStore
    if($srcMsg -notlike ""){
        Write-Host $srcMsg -BackgroundColor Black -ForegroundColor Red
        $srcMsg += "  Script Terminated."
        Write-EventLog -LogName Application -Source $replication -EventId 4 -EntryType Error -Message $srcmsg -Category 0
        exit
    }
    if($dstMsg -notlike ""){
        Write-Host $dstMsg -BackgroundColor Black -ForegroundColor Red
        $dstMsg += "  Script Terminated."
        Write-EventLog -LogName Application -Source $replication -EventId 4 -EntryType Error -Message $dstmsg -Category 0
        exit
    }
    if(($srcMsg -like "") -and ($dstMsg -like "")){ 
        if($vDisksToExport.Length -ne 0){
            $exportMsg = Validate-ExportList -server $srcServer -list $vDisksToExport
            if($exportMsg -notlike ""){
                Write-Host $exportMSG -BackgroundColor Black -ForegroundColor Red
                $exportMsg += ".  Script Terminated."
                Write-EventLog -LogName Application -Source $replication -EventId 5 -EntryType Error -Message $exportMsg -Category 0
                exit
            }
        } else {
            Set-PvsConnection -Server $srcServer -Port 54321 | Out-Null
            $exportMsg = "No list of vDisks to export found.  Exporting ALL vDisks in the $srcStore vDisk store on $srcServer."
            Write-EventLog -LogName Application -Source $replication -EventId 6 -EntryType Warning -Message $exportMsg -Category 0
            $vDisksToExport = Get-PvsDiskLocator -StoreName $srcStore -SiteName $srcSite | Select-Object -ExpandProperty DiskLocatorName
        }
        $cred = Get-Credential $env:userDomain\$env:userName
        START-REPLICATION -cred $cred -srcServer $srcServer -srcSite $srcSite -srcStore $srcStore -vDisksToExport $vDisksToExport -dstServer $dstServer -dstSite $dstSite -dstStore $dstStore -eventLog $replication
        $finalmsg = "vDisk Replication Script Complete."
        Write-EventLog -LogName Application -Source $replication -EventId 11 -EntryType Information -Message $finalmsg -Category 0
    } else {
        #SHOULDN"T EVER BE HERE
		Throw "UNEXPECTED ERROR"
    }
}

