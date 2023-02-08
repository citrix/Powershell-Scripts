<#
.SYNOPSIS
    Diagnosing and (semi-) automatically resolving VMs on Citrix Virtual Apps and Desktops (CVAD) in an unknown power state. 
.DESCRIPTION
    Get-ProvVmInUnknownPowerState diagnoses the VMs on CVAD in an unknown power state, reports the causes, and (semi-) automatically fixes the causes. 
    Specifically, Get-ProvVmInUnknownPowerState utilizes the names of VMs on CVAD to find the corresponding VMs on hypervisors and check three scenarios below that can make the power state of the VMs unknown.
        Scenario 1: the state of the hypervisor connection is unavailable. such as connection credentials being invalid.
        Scenario 2: the VMs on the hypervisor are deleted.
        Scenario 3: the IDs of VMs on CVAD mismatches the corresponding IDs of the VM on hypervisors. 

    In case of scenario 1 and 2, Get-ProvVmInUnknownPowerState reports the causes of the unknown power state and provide suggestions to help admins fix the issues, such as correcting the credentials or deleting the VMs on CVAD. 
    In the case of scenario 3, Get-ProvVmInUnknownPowerState reports the causes and suggestions. 
    If the "-Fix" parameter is specified, Get-ProvVmInUnknownPowerState fixes the causes of scenario 3 automatically.
    The scenario 1, 2, and 3 are exclusive. If the connection is unavailable, it is not possible to access the hypervisor; consequently, check whether the corresponding VM on the hypervisor is deleted or the IDs are matched.
.INPUTS
    Get-ProvVmInUnknownPowerState can take a hypervisor connection name, a broker catalog name, and/or "-Fix" as input.
.OUTPUTS
    1. If either a hypervisor connection name or a broker catalog is given, then Get-ProvVmInUnknownPowerState reports the VMs in an unknown power state associated with the hypervisor connection name or the broker catalog.
    2. If both a hypervisor connection name and a broker catalog are given, then Get-ProvVmInUnknownPowerState reports the VMs associated with the broker catalog, because the VMs on the catalog is a subset of the VMs on the hypervisor connection
    3. Without the "-Fix" parameter, the admin can get the report that includes the list of the VMs with the unknown power states together with the causes and suggestions.
    4. With the parameter "-Fix", the admin can get the report, and the script automatically resolved the issue of scenario 3 by updating the IDs of VMs. 
.PARAMETER HypervisorConnectionName
    The name of the hypervisor connection. Report the VMs associated with the hypervisor connection.
.PARAMETER BrokerCatalogName
    The name of the broker catalogue name. Report the VMs associated with the catalog.
.PARAMETER Fix
    Update the UUIDs of VMs automatically to resolve the mismatched UUID issue.
.NOTES
    Version      : 1.0.1
    Author       : Citrix Systems, Inc.
.EXAMPLE
    Get-ProvVmInUnknownPowerState
.EXAMPLE
    Get-ProvVmInUnknownPowerState -Fix
.EXAMPLE
    Get-ProvVmInUnknownPowerState -HypervisorConnectionName "ExampleConnectionName" -Fix
#>

Param(
    [Parameter(Mandatory=$false)]
    [string]$HypervisorConnectionName,
    [Parameter(Mandatory=$false)]
    [string]$BrokerCatalogName, 
    [Parameter(Mandatory=$false)]
    [switch]$Fix
)

# Add XDHyp
Add-PSSnapin -Name "Citrix.Broker.Admin.V2","Citrix.Host.Admin.V2"

# Get unavailable hypervisor connections.
function Get-ConnectionUnavailable {
    $connectionsUnavailable = [System.Collections.ArrayList]::new()

    # If a hypervisor is specified an an input, check the hypervisor connection associated the input.
    if ($BrokerCatalogName) {
        try {
            $connName = (Get-BrokerMachine -CatalogName $BrokerCatalogName -Property @("HypervisorConnectionName") -MaxRecordCount 1).HypervisorConnectionName
            $connection = Get-BrokerHypervisorConnection -Name $connName -Property @("Name", "HypHypervisorConnectionUid", "State", "FaultState")
            if ($connection.State -eq "Unavailable") {
                return $connection
            }
            return $null
        }
        catch {
            Write-Error -Message "Failed while getting connections unavailables. Check the input broker catalog $($BrokerCatalogName) and the associated connection." -ErrorAction Stop
        }
    }
    # If a catalog is specified an an input, check the hypervisor connection associated the input.
    elseif ($HypervisorConnectionName) {
        try {
            $connection = Get-BrokerHypervisorConnection -Name $HypervisorConnectionName -Property @("Name", "HypHypervisorConnectionUid", "State", "FaultState")
            if ($connection.State -eq "Unavailable") {
                return $connection
            }
            return $null
        }
        catch {
            Write-Error -Message "Failed while getting connections unavailables. Check the input hypervisor connection $($HypervisorConnectionName)." -ErrorAction Stop
        }
    }
    # else check all hypervisor connections
    else {
        try {
            # Get the total connection count. 
            Get-BrokerHypervisorConnection -State "Unavailable" -ReturnTotalRecordCount -MaxRecordCount 0 -ErrorVariable resultsCount -ErrorAction SilentlyContinue
            $totalCount = $resultsCount[0].TotalAvailableResultCount   
            $currentCount = 0
            $skipCount = 0
            
            # Get the hypervisor connections unavailable. Each iteration can receive maximum 250 records only. 
            while ($skipCount -lt $totalCount) {
                # Get 250 connections unavailable.
                $partialConnections = Get-BrokerHypervisorConnection -MaxRecordCount 250 -Skip $skipCount -State "Unavailable" -Property @("Name", "HypHypervisorConnectionUid", "FaultState")
                
                # Add the hypervisor connections
                [void]$connectionsUnavailable.Add($partialConnections)

                # Increase the skip count to check the remaining connections. 
                $skipCount += 250

                # Count the connections checked.
                $currentCount = $partialConnections.Count
                Write-Host "Checked $($currentCount) unavailable connections out of $($totalCount) unavailable connections ($($currentCount / $totalCount * 100))%."
            }

            # return the total connections
            return $connectionsUnavailable
        }
        catch {
            Write-Error -Message "Failed while getting connections unavailables. Check Get-BrokerHypervisorConnection to get more than 250 records." -ErrorAction Stop
        }
    }
}


# Get the actual VMs on hypervisors.
function Get-VmOnHypervisor {
    Param ($UnavailableConnection)
    
    # Get VMs on the Hypervisor. If the connection is unavailable, ignore the connection. 
    $vmList = [System.Collections.ArrayList]::new()
    $previousCount = 0

    try {
        Get-ChildItem -Path @('XDHyp:\Connections') | Where-Object {$UnavailableConnection.Name -NotContains $_.HypervisorConnectionName} | ForEach-Object {
            # If a catalog is specified an an input, get the VMs associated to the catalog only.
            if ($BrokerCatalogName) {
                try {
                    $connName = (Get-BrokerMachine -CatalogName $BrokerCatalogName -Property @("HypervisorConnectionName") -MaxRecordCount 1).HypervisorConnectionName
                    if ($_.HypervisorConnectionName -eq $connName) {
                        Write-Host "Checking the VMs on $($_.ConnectionTypeName), where the connection $($connName) connects to"
                        Find-VMs -Path $_.PSPath -Connection $_.HypervisorConnectionName -VmList $vmList
                        Write-Host "Checked $($vmList.Count - $previousCount) VMs using the connection $($_.HypervisorConnectionName)."
                    }
                }
                catch {
                    Write-Error -Message "Failed while getting VMs on XDHyp. Check the broker catalog $($BrokerCatalogName) and $($_.PSPath)." -ErrorAction Stop
                }
            }
            # If a hypervisor is specified an an input, get the VMs associated to the connection only.
            elseif ($HypervisorConnectionName) {
                try {
                    # If the current connection equals to the input connection, then find the VMs on the connection.
                    if ($_.HypervisorConnectionName -eq $HypervisorConnectionName) {
                        Write-Host "Checking the VMs on $($_.ConnectionTypeName), where the connection $($_.HypervisorConnectionName) connects to"
                        Find-VMs -Path $_.PSPath -Connection $_.HypervisorConnectionName -VmList $vmList
                        Write-Host "Checked $($vmList.Count - $previousCount) VMs using the connection $($_.HypervisorConnectionName)."
                    }
                }
                catch {
                    Write-Error -Message "Failed while getting VMs on XDHyp. Check the hypervisor conection $($HypervisorConnectionName) and $($_.PSPath)." -ErrorAction Stop
                }
            }
            # Else, find VMs on all hypervisor connections. 
            else {
                try {
                    Write-Host "Checking the VMs using the connection $($_.HypervisorConnectionName)"
                    $previousCount = $vmList.Count
                    Find-VMs -Path $_.PSPath -Connection $_.HypervisorConnectionName -VmList $vmList
                    Write-Host "Checked $($vmList.Count - $previousCount) VMs using the connection $($_.HypervisorConnectionName)."
                }
                catch {
                    Write-Error -Message "Failed while getting VMs on XDHyp. Check $($_.PSPath)." -ErrorAction Stop
                }
            }
        }
        return $vmList
    }
    catch {
        Write-Error -Message "Failed while getting VMs on XDHyp." -ErrorAction Stop
    }
}

# Get the actual VMs on hypervisors.
function Find-VMs {
    param ($Path, $ConnectionName, $VmList)

    try {
        Get-ChildItem -LiteralPath @($Path) -Force | ForEach-Object {
            # If the item is VM, then add it to the VM list
            if ($_.ObjectType -eq "Vm") {
                $vm = $_ | Select-Object FullName, Id, HypervisorConnectionName
                $vm.HypervisorConnectionName = $ConnectionName
                [void]$VmList.Add($vm)
            }
            # If the item contains sub-items, the travel the item as well
            if ( ($_.PSIsContainer -eq $true) -or ($_.IsContainer -eq $true)) {
                Find-VMs -Path $_.PSPath -Connection $ConnectionName -VmList $vmList
            }
        }
    }
    catch {
        Write-Error -Message "Failed while finding VMs on $($Path)." -ErrorAction Stop
    }
}

# Get the VMs on Broker in an Unknown Power State.
function Get-VmOnBroker {
    $vmsUnknown = [System.Collections.ArrayList]::new()

    # Get the total number of VMs in an unknown state. If a catalog or a hypervisor connection is specified, then count the VMs associated to the input only.
    try {
        if ($BrokerCatalogName) {
            Get-BrokerMachine -PowerState "Unknown" -CatalogName $BrokerCatalogName -ReturnTotalRecordCount -MaxRecordCount 0 -ErrorVariable resultsCount -ErrorAction SilentlyContinue
        }
        elseif ($HypervisorConnectionName) {
            Get-BrokerMachine -PowerState "Unknown" -HypervisorConnectionName $HypervisorConnectionName -ReturnTotalRecordCount -MaxRecordCount 0 -ErrorVariable resultsCount -ErrorAction SilentlyContinue
        }
        else {
            Get-BrokerMachine -PowerState "Unknown" -ReturnTotalRecordCount -MaxRecordCount 0 -ErrorVariable resultsCount -ErrorAction SilentlyContinue
        }
        $totalCount = $resultsCount[0].TotalAvailableResultCount
        if ($totalCount -eq 0) {
            Write-Host "No VMs are in an unknown power state."
            exit
        }
    }
    catch {
        Write-Error -Message "Failed while getting the total number of VMs on CVAD in an unknown power state." -ErrorAction Stop
    }
   
    # Get the VMs with the unknown power state. Each iteration can receive maximum 250 records only. 
    $currentCount = 0
    $skipCount = 0
    
    try {
        while ($skipCount -lt $totalCount) {
            # If a catalog name is specified in the input
            if ($BrokerCatalogName) {
                # Get 250 VMs in an unknown power state associated to the specified broker catalog.
                $partialVMs = Get-BrokerMachine -PowerState "Unknown" -MaxRecordCount 250 -Skip $skipCount -CatalogName $BrokerCatalogName -Property @("HostedMachineName", "HostedMachineId", "CatalogName", "CatalogUUID", "HypervisorConnectionName", "HypHypervisorConnectionUid")
            } 
            # If a hypervisor name is specified in the input
            elseif ($HypervisorConnectionName) {
                # Get 250 VMs in an unknown power state associated to the specified hypervisor connection.
                $partialVMs = Get-BrokerMachine -PowerState "Unknown" -MaxRecordCount 250 -Skip $skipCount -HypervisorConnectionName $HypervisorConnectionName -Property @("HostedMachineName", "HostedMachineId", "CatalogName", "CatalogUUID", "HypervisorConnectionName", "HypHypervisorConnectionUid")
            } 
            # If there is no input
            else {
                # Get 250 VMs in an unknown power state.
                $partialVMs = Get-BrokerMachine -PowerState "Unknown" -MaxRecordCount 250 -Skip $skipCount -Property @("HostedMachineName", "HostedMachineId", "CatalogName", "CatalogUUID", "HypervisorConnectionName", "HypHypervisorConnectionUid")
            }
    
            # Count the VMs loaded.
            $currentCount = $partialVMs.Count
            Write-Host "Checked $($currentCount) VMs out of $($totalCount) VMs ($($currentCount / $totalCount * 100)%)."
            
            # Add the VMs in an unknown power state
            $partialVMs = $partialVMs | Select-Object HostedMachineName, HostedMachineId, CatalogName, CatalogUUID, HypervisorConnectionName, HypHypervisorConnectionUid, Cause, Suggestion
            [void]$vmsUnknown.Add($partialVMs)
    
            # Increase the skip count to check the remaining VMs. 
            $skipCount += 250
        }
    
        # return the total VMs
        return $vmsUnknown
    }
    catch {
        Write-Error -Message "Failed while getting partial VMs on CVAD in an unknown power state." -ErrorAction Stop
    }
}

# Main logic.
function Get-VMsInUnknownPowerState {       
    $result = [System.Collections.ArrayList]::new()

    # Get the hypervisor connections that have unavailable state
    Write-Host "1. Checking the states of hypervisor connections."
    $connectionsUnavailable = Get-ConnectionUnavailable

    # Get the VMs in an unknown power state.
    Write-Host "2. Checking the VMs on CVAD in an unknown power state."
    $vmsUnknown = Get-VmOnBroker

    # Get actual VMs on hypervisors
    Write-Host "3. Checking VMs on hypervisors corresponding to the VMs on CVAD."
    $vmsOnHyp = Get-VmOnHypervisor -UnavailableConnection $connectionsUnavailable
   
    # Iterate each VM in an Unknown Power State.
    Write-Host "4. Reporting (and Fixing) the VMs in an unknown power state."
    
    try {
        $vmsUnknown | ForEach-Object -Process { 
            # Scenario 1: Broken Host Connections.
            # Get the host connection state that the VM is associated.
            $connection = $connectionsUnavailable | Where-Object HypHypervisorConnectionUid -eq $_.HypHypervisorConnectionUid
            if ($connection -ne $null) {
                $_.Cause = "The hypervisor connection is unavailable due to $($connection.FaultState)."
                $_.Suggestion = "Check the hypervisor connection named $($connection.Name)."
            }
            # Scenario 2: VMs are deleted.
            elseif ($vmsOnHyp.FullName -NotContains $($_.HostedMachineName + ".vm")) {
                $_.Cause = "The VM on the hypervisor is deleted."
                $_.Suggestion = "Check whether the VM still exists on the hypervisor and then update CVAD."
            }
            # Scenario 3: the id of the VM on CVAD is mismatched with the id of the corresponding VM on the hypervisor.
            elseif ($vmsOnHyp.FullName -Contains $($_.HostedMachineName + ".vm")) {
                $curVmOnHyp = $vmsOnHyp | Where-Object FullName -eq $($_.HostedMachineName + ".vm") 
                if ($curVmOnHyp.Id -ne $_.HostedMachineId) {
                    $_.Cause = "The ID of the VM on CVAD is mismatched with the ID of the corresponding VM on the hypervisor."
                    # if -Fix parameter is given, then update the VM ID.
                    if ($Fix) {
                        try {
                            Get-BrokerMachine -HostedMachineName $_.HostedMachineName | Set-BrokerMachine -HostedMachineId $curVmOnHyp.Id
                        } 
                        catch {
                            $_.Cause = "Failed to fix the mismatched IDs of VMs."
                            $_.Suggestion = "Update the VM ID with $($curVmOnHyp.Id), then restart the broker service. `n option 1) To fix it automatiicaly, Get-MachineUnknown -Fix `n option 2) To fix it manually, Get-BrokerMachine -HostedMachineName ""$($_.HostedMachineName)"" | Set-BrokerMachine -HostedMachineId ""$($curVmOnHyp.Id)"""
                        }
                        $_.Suggestion = "The VM ID is updated with $($curVmOnHyp.Id), then restart the broker service."
                    } else {
                        # If -Fix parameter is not given, then provide a way to fix the ID manually
                        $_.Suggestion = "Update VM ID with $($curVmOnHyp.Id), then restart the broker service. `n option 1) To fix it automatiicaly, Get-ProvVmInUnknownPowerState -Fix `n option 2) To fix it manually, Get-BrokerMachine -HostedMachineName ""$($_.HostedMachineName)"" | `nSet-BrokerMachine -HostedMachineId ""$($curVmOnHyp.Id)"""
                    }
                }
                else {
                    # After fixing the mismatche ID issue, but the broker service is not restarted properly yet.
                    $_.Cause = "Please make sure the broker service is restarted properly."
                    $_.Suggestion = "Restart the broker service or wait for the broker service to be restarted."
                }
            }
            # Exeptional cases. The broker service is not restarted properly yet.
            else {
                $_.Cause = "Please make sure the broker service is restarted properly."
                $_.Suggestion = "Restart the broker service or wait for the broker service to be restarted."
            }
            [void]$result.Add($_)
        }
    }
    catch {
        Write-Error -Message "Failed while updating the cause and suggestion for $($_.HostedMachineName)." -ErrorAction Stop
    }
    
    return $result
}

# Begining of Get-ProvVmInUnknownPowerState.
$result = Get-VMsInUnknownPowerState
return $result
