<#
.SYNOPSIS
    Monitors current machine usage and creates or deletes machines based on
    administrator configured values.

.DESCRIPTION
    This script is meant to monitor load accross a Citrix Delivery Group and
    create\delete machines when crossing the configured watermarks.

    It runs as a per-run driven state machine, which means it will only process
    one state per run of the script. This means the script should be run at
    regular intervals in order to monitor, create, and delete machines as needed.

    The first run of the script must contain ALL parameters except the script tag
    (if the default is desired). On subsequent runs, only the DeliveryGroupName is
    required, and optionally watermarks can be updated. Both watermarks must be
    updated at once.

    There are some prerequisites in order to run the script:
      1. There must be a delivery group created to be monitored
      2. There must be a machine catalog that is of type MCS and has an associated Provisioning Scheme (image)
      3. The Provisioning Scheme must have an associated IdentityPool
      4. Writing to Event Logs requires an event log source to be created before passing
        it in to this script. See the New-EventLog cmdlet.
      5. In order to handle remote authentication, you must set up an API Key and set the
        credentials (using the same User Account under which the script will run).
        The required command looks like this: 
            'Set-XDCredentials -APIKey <key_id> -CustomerId <customer_id> -SecretKey <secret_key -StoreAs <name>'
        where you will pass the <name> to this script under the XdProfileName parameter.
        (see Set-XDCredentials)

    If setting this up with Task Scheduler, make sure to enable the setting that
    does not start a new instance if this one is already running.

.PARAMETER DeliveryGroupName
    Semi-colon-separated list of the Delivery Group Name(s) to monitor and take actions on.
    When performining initialization or updating (e.g. passing in Watermarks, MaximumCreatedMachines, etc.)
    only one Delivery Group at a time is supported. The exception is 'EventLogSource' in which
    case it will be set for all the passed in Delivery Groups.
.PARAMETER XdProfileName
    Name of the profile to use for remote authentication with Citrix Servers
.PARAMETER LowWatermark
    Load percentage at which previously script-created machines in the given
    delivery group will be deleted
.PARAMETER HighWatermark
    Load percentage at which new machines will be created and deployed
.PARAMETER MachineCatalogName
    Name of the machine catalog where machines will be created
.PARAMETER ScriptTag
    Tag that will be used to track the created machines
.PARAMETER EventLogSource
    Name of the Event Log Source to write to. It is important to pass a meaningful
    name here in order to find the logs.
.PARAMETER MaximumCreatedMachines
    The maximum amount of machines that will be created in the specified delivery group

.NOTES
    Version      : 1.0.1
    Author       : Citrix Systems, Inc.
    Creation Date: 07 November 2019
    Log          : Added MaximumCreatedMachines parameter

.EXAMPLE
    Invoke-AutoscaleMachineCreation -DeliveryGroupName DevTest -XdProfileName TestProfile
#>

# ============================================================================
# Copyright Citrix Systems, Inc. All rights reserved.
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [String]$DeliveryGroupName,
    [Parameter(Mandatory=$true)]
    [String]$XdProfileName,
    [Parameter(Mandatory=$false)]
    [Int]$LowWatermark = -1,
    [Parameter(Mandatory=$false)]
    [Int]$HighWatermark = -1,
    [Parameter(Mandatory=$false)]
    [String]$MachineCatalogName,
    [Parameter(Mandatory=$false)]
    [String]$ScriptTag = 'AutoscaleScripted',
    [Parameter(Mandatory=$false)]
    [String]$EventLogSource = $null,
    [Parameter(Mandatory=$false)]
    [Int]$MaximumCreatedMachines = -1
)

# ============================================================================
# State Machine
# ============================================================================

# Definitions ----------------------------------------------------------------
Add-Type -TypeDefinition @"
    public enum AutoscaleScriptState
    {
        MonitorUsage,
        ProvisionMachines,
        MonitorProvision,
        AddMachines,
        RemoveMachines,
        MonitorDeleteMachines
    }
"@

# MetaData Names -------------------------------------------------------------
$AutoscaleMetadataNames = @{
    'State'                  = 'Citrix_AutoscaleScript_State';
    'CleanExit'              = 'Citrix_AutoscaleScript_CleanExit';
    'Tag'                    = 'Citrix_AutoscaleScript_MachineTag';
    'MachineCatalogName'     = 'Citrix_AutoscaleScript_MachineCatalogName';
    'IdentityPoolUid'        = 'Citrix_AutoscaleScript_IdentityPoolUid';
    'ProvSchemeUid'          = 'Citrix_AutoscaleScript_ProvSchemeUid';
    'ProvTask'               = 'Citrix_AutoscaleScript_ProvTaskId';
    'HighWatermark'          = 'Citrix_AutoscaleScript_HighWatermark';
    'LowWatermark'           = 'Citrix_AutoscaleScript_LowWatermark';
    'MaximumCreatedMachines' = 'Citrix_AutoscaleScript_MaximumCreatedMachines';
    'CurrentLoad'            = 'Citrix_AutoscaleScript_CurrentLoad';
    'Actions'                = 'Citrix_AutoscaleScript_ActionsTaken';
    'EventLogSource'         = 'Citrix_AutoscaleScript_EventLogSource';
    'LastUpdateTime'         = 'Citrix_AutoscaleScript_LastUpdateTime';
}

# States ---------------------------------------------------------------------
function Watch-AutoscaleLoadBalance
{
    param([object]$DeliveryGroup)

    if ($DeliveryGroup.TotalDesktops -le 0)
    {
        # No action to take in an empty delivery group
        return
    }

    $currentLoad = [math]::Round((Measure-DeliveryGroupLoad $DeliveryGroup), 2)
    $lowWm = [int]($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['LowWatermark']])
    $highWm = [int]($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['HighWatermark']])

    if ($currentLoad -gt $highWm)
    {
        $machines = @(Get-BrokerMachine -Tag ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['Tag']]) -DesktopGroupUid $DeliveryGroup.Uid -Property Uid)
        $maxCount = [int]($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['MaximumCreatedMachines']])

        if ($maxCount -gt 0 -and $machines.Count -ge $maxCount)
        {
            # We cannot create any more machines
            Write-Log "Cannot provision any more machines. Upper limit of [$maxCount] has been reached." -DgName $DeliveryGroup.Name
            return
        }

        Write-Log "Provisioning more machines. Current Usage [$currentLoad] >= High Watermark [$highWm]." -DgName $DeliveryGroup.Name
        $map = @{ `
            ($AutoscaleMetadataNames['CurrentLoad']) = [string]($currentLoad); `
            ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::ProvisionMachines); `
        }
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
    }
    elseif ($currentLoad -lt $lowWm)
    {
        $machines = @(Get-BrokerMachine -Tag ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['Tag']]) -DesktopGroupUid $DeliveryGroup.Uid -SessionCount 0 -Property Uid)
        if ($machines.Count -eq 0)
        {
            # There are no machines available to be removed
            return
        }

        Write-Log "Removing extraneous machines: Current Usage [$currentLoad] <= Low Watermark [$lowWm]." -DgName $DeliveryGroup.Name
        $map = @{ `
            ($AutoscaleMetadataNames['CurrentLoad']) = [string]($currentLoad); `
            ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::RemoveMachines); `
        }
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
    }
}

function Publish-Machines
{
    param([object]$DeliveryGroup)

    $maxCount = [int]($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['MaximumCreatedMachines']])
    $machinesToCreate = (Measure-HighWatermarkDelta $DeliveryGroup)

    if ($maxCount -gt 0)
    {
        $machines = @(Get-BrokerMachine -Tag ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['Tag']]) -DesktopGroupUid $DeliveryGroup.Uid -Property Uid)
        $machinesToCreate = [math]::Min(($maxCount - $machines.Count), $machinesToCreate)

        if ($machinesToCreate -le 0)
        {
            Write-Log "Cannot provision any more machines, reached limit of [$maxCount]" -DgName $DeliveryGroup.Name
            $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
            return
        }
    }

    $adAccounts = New-AcctADAccount -IdentityPoolUid ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['IdentityPoolUid']]) -Count $machinesToCreate

    if ($adAccounts.SuccessfulAccountsCount -le 0)
    {
        Write-Log "Failed to create new accounts using Identity Pool [$($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['IdentityPoolUid']])]." -DgName $DeliveryGroup.Name
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
        return
    }

    if ($adAccounts.FailedAccountsCount -gt 0)
    {
        Write-Log "Failed to create [$($adAccounts.FailedAccountsCount)] accounts. Accounts: [$($adAccounts.FailedAccounts)]" -DgName $DeliveryGroup.Name
    }
    
    $provTask = New-ProvVM -ProvisioningSchemeUid ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['ProvSchemeUid']]) -ADAccountName $adAccounts.SuccessfulAccounts -RunAsynchronously

    Write-Log "Began provisioning of [$($adAccounts.SuccessfulAccountsCount)] machines to [$($DeliveryGroup.Name)]. Monitoring task [$($provTask.Guid)]." -DgName $DeliveryGroup.Name
    $map = @{ `
        ($AutoscaleMetadataNames['ProvTask']) = [string]($provTask.Guid); `
        ($AutoscaleMetadataNames['Actions']) = [string]($adAccounts.SuccessfulAccountsCount); `
        ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::MonitorProvision); `
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
}

function Watch-MachineDeployment
{
    param([object]$DeliveryGroup)

    $provTaskId = ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['ProvTask']])
    $provTask = Get-ProvTask -TaskId $provTaskId

    # Sanity Check that the task we're monitoring is creating new machines
    if ($provTask.Type -ne "NewVirtualMachine")
    {
        Write-Log "Assertion failed: Task type [$($provTask.Type)] is not expected for machine deployment." -DgName $DeliveryGroup.Name
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
        return
    }

    if ($provTask.Active -eq $true)
    {
        # Provisioning is on-going
        return
    }

    Write-Log "Provisioning task [$provTaskId] is complete. [$($provTask.VirtualMachinesCreatedCount)] created. [$($provTask.VirtualMachinesCreationFailedCount)] failed to create." -DgName $DeliveryGroup.Name

    if ($provTask.VirtualMachinesCreatedCount -le 0)
    {
        Write-Log "Failed to create any machines. Error [$($provTask.FailedVirtualMachines.Status)]" -DgName $DeliveryGroup.Name
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
        return
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::AddMachines)
}

function Add-MachinesToDesktopGroup
{
    param([object]$DeliveryGroup)

    # Get Machines Created by ProvTask
    $provTaskId = ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['ProvTask']])
    $provTask = Get-ProvTask -TaskId $provTaskId

    # Add machines to catalog
    $catalog = Get-BrokerCatalog -Name ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['MachineCatalogName']])
    $machines = @()
    $provTask.CreatedVirtualMachines | ForEach-Object -Process { $machines += New-BrokerMachine -MachineName $_.VmName -CatalogUid $catalog.Uid}

    # Add tag to created machines and add them to the delivery group
    $machines | Add-BrokerTag ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['Tag']]) 
    $machines | Add-BrokerMachine -DesktopGroup $DeliveryGroup

    Write-Log "Added [$($machines.Count)] machines to [$($DeliveryGroup.Name)]." -DgName $DeliveryGroup.Name

    $map = @{ `
        ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::MonitorUsage); `
        ($AutoscaleMetadataNames['LastUpdateTime']) = (Get-CurrentTimeString); `
    }
    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
}

function Remove-MachinesFromDesktopGroup
{
    param([object]$DeliveryGroup)

    $machines = @(Get-BrokerMachine -Tag ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['Tag']]) `
                 -DesktopGroupUid $DeliveryGroup.Uid `
                 -SessionCount 0 `
                 -Property MachineName,HostedMachineName)
    if ($machines.Count -le 0)
    {
        # No machines can be removed
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
        return
    }
    # Remove from Delivery Group
    $machines | Remove-BrokerMachine -DesktopGroup $DeliveryGroup
    # Remove from the Broker database
    $machines | Remove-BrokerMachine

    # Remove from Hypervisor and MCS database
    $machineNames = $machines | ForEach-Object {$_.HostedMachineName}
    $provTask = Remove-ProvVM -ProvisioningSchemeUid ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['ProvSchemeUid']]) -VMName $machineNames -RunAsynchronously

    Write-Log "Removing [$($machines.Count)] machines from [$($DeliveryGroup.Name)]. Monitoring task [$($provTask.Guid)]" -DgName $DeliveryGroup.Name
    $map = @{ `
        ($AutoscaleMetadataNames['ProvTask']) = [string]($provTask.Guid); `
        ($AutoscaleMetadataNames['Actions']) = [string]($machines.Count); `
        ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::MonitorDeleteMachines); `
        ($AutoscaleMetadataNames['LastUpdateTime']) = (Get-CurrentTimeString); `
    }
    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
}

function Watch-MachineDeletion
{
    param([object]$DeliveryGroup)

    $provTaskId = ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['ProvTask']])
    $provTask = Get-ProvTask -TaskId $provTaskId

    # Sanity Check that the task we're monitoring is deleting machines
    if ($provTask.Type -ne "RemoveVirtualMachine")
    {
        Write-Log "Assertion failed: Task type [$($provTask.Type)] is not expected for machine deletion." -DgName $DeliveryGroup.Name
        $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
        return
    }

    if ($provTask.Active -eq $true)
    {
        # Machine removal is on-going
        return
    }

    Write-Log "Machine deletion task [$provTaskId] is [$($provTask.TaskState)]." -DgName $DeliveryGroup.Name

    $adAccounts = $provTask.RemovedVirtualMachines | ForEach-Object {$_.ADAccountName}
    if ($adAccounts.Count -gt 0)
    {
        $result = Remove-AcctADAccount `
                    -IdentityPoolUid ($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['IdentityPoolUid']]) `
                    -ADAccountName $adAccounts `
                    -RemovalOption Delete

        if ($result.FailedAccountsCount -gt 0)
        {
            Write-Log "Failed to remove [$($result.FailedAccountsCount)] out of [$($adAccounts.Count)] accounts. Accounts: [$($result.FailedAccounts)]." -DgName $DeliveryGroup.Name
        }
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['State'] -Value ([AutoscaleScriptState]::MonitorUsage)
}

# State Machine --------------------------------------------------------------
function Initialize-StateMachine
{
    param([object]$DeliveryGroup)

    # Validate Incoming Parameters
    if ((Confirm-IncomingParameters $DeliveryGroup) -eq $false)
    {
        throw "Invalid parameters used to initialize autoscale machine creation."
    }

    $catalog = Get-BrokerCatalog -Name $MachineCatalogName -Property ProvisioningSchemeId
    $provScheme = Get-ProvScheme -ProvisioningSchemeUid ($catalog.ProvisioningSchemeId)

    # Add Initial MetaData to Delivery Group
    $map = @{ `
        ($AutoscaleMetadataNames['Tag']) = ($ScriptTag); `
        ($AutoscaleMetadataNames['CleanExit']) = "False"; `
        ($AutoscaleMetadataNames['State']) = [string]([AutoscaleScriptState]::MonitorUsage); `
        ($AutoscaleMetadataNames['MachineCatalogName']) = ($MachineCatalogName); `
        ($AutoscaleMetadataNames['IdentityPoolUid']) = [string]($provScheme.IdentityPoolUid); `
        ($AutoscaleMetadataNames['ProvSchemeUid']) = [string]($provScheme.ProvisioningSchemeUid); `
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
    Edit-Watermarks $DeliveryGroup

    # Create the script tag, ignoring an error if it has been created before
    New-BrokerTag ($ScriptTag) -ErrorAction SilentlyContinue | Out-Null

    return [AutoscaleScriptState]::MonitorUsage
}

function Resume-AutoscaleStateMachine
{
    param(
        [AutoscaleScriptState]$CurrentState,
        [object]$DeliveryGroup
    )

    Write-Log "Entering State: [$CurrentState] and the last run was successful: [$($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['CleanExit']])]." `
        -Trivial $true `
        -DgName $DeliveryGroup.Name
    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['CleanExit'] -Value $false

    switch ($CurrentState)
    {
        MonitorUsage          { Watch-AutoscaleLoadBalance $DeliveryGroup; break }
        ProvisionMachines     { Publish-Machines $DeliveryGroup; break }
        MonitorProvision      { Watch-MachineDeployment $DeliveryGroup; break }
        AddMachines           { Add-MachinesToDesktopGroup $DeliveryGroup; break }
        RemoveMachines        { Remove-MachinesFromDesktopGroup $DeliveryGroup; break }
        MonitorDeleteMachines { Watch-MachineDeletion $DeliveryGroup; break }
        Default               { Write-Log "No action taken for [$($CurrentState)] state" -DgName $DeliveryGroup.Name }
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['CleanExit'] -Value $true
}

# ============================================================================
# Helper Functions
# ============================================================================

function Measure-DeliveryGroupLoad
{
    param([object]$DeliveryGroup)

    if ($DeliveryGroup.SessionSupport -eq 'SingleSession')
    {
        return ($DeliveryGroup.Sessions * 100 / $DeliveryGroup.TotalDesktops) 
    }

    $machineLoadArray = Get-BrokerMachine -DesktopGroupUid $DeliveryGroup.Uid -Property LoadIndex
    $totalLoad = $machineLoadArray | ForEach-Object -Begin { $total = 0 } -Process { $total += $_.LoadIndex } -End { $total }

    # Maximum load index per machines is a hard-coded number, for more information see:
    #   https://docs.citrix.com/en-us/citrix-virtual-apps-desktops-service/manage-deployment/autoscale.html
    $maxLoad = 10000 * $machineLoadArray.Count

    return ($totalLoad * 100 / $maxLoad)
}

function Measure-HighWatermarkDelta
{
    param([object]$DeliveryGroup)

    $highWm = [int]($DeliveryGroup.MetadataMap[$AutoscaleMetadataNames['HighWatermark']])

    if ($DeliveryGroup.SessionSupport -eq 'SingleSession')
    {
        return [math]::Ceiling((100 * $DeliveryGroup.Sessions) / $highWm - $DeliveryGroup.TotalDesktops)
    }

    $machineLoadArray = Get-BrokerMachine -DesktopGroupUid $DeliveryGroup.Uid -Property LoadIndex
    $totalLoad = $machineLoadArray | ForEach-Object -Begin { $total = 0 } -Process { $total += $_.LoadIndex } -End { $total }
    
    # Maximum load index per machines is a hard-coded number, for more information see:
    #   https://docs.citrix.com/en-us/citrix-virtual-apps-desktops-service/manage-deployment/autoscale.html
    return [math]::Ceiling(($totalLoad * 100 / 10000) / $highWm - $machineLoadArray.Count)
}

function Confirm-IncomingParameters
{
    param([object]$DeliveryGroup)
    # Stop at any error
    $ErrorActionPreference = 'Stop'
    $dgName = $DeliveryGroup.Name

    # Set to default if LowWatermark\HighWatermark was not set
    if ($LowWatermark -le 0)
    {
        $script:LowWatermark = 15
        $script:HighWatermark = 80
        Write-Log "Assuming default values for watermarks [$LowWatermark : $HighWatermark]." -DgName $dgName
    }

    # Machine Catalog
    $catalog = Get-BrokerCatalog -Name $MachineCatalogName
    if ($catalog.MachinesArePhysical)
    {
        Write-Log "Given catalog [$MachineCatalogName] only supports physical machines" -DgName $dgName
        return $false
    }

    if ($catalog.ProvisioningType -ne "MCS")
    {
        Write-Log "Given catalog [$MachineCatalogName] is not set to use Machine Creation Services." -DgName $dgName
        return $false
    }

    if ($catalog.SessionSupport -ne $DeliveryGroup.SessionSupport)
    {
        Write-Log "Given catalog [$MachineCatalogName] has a different SessionSupport than the delivery group." -DgName $dgName
        return $false
    }

    if ($null -eq $catalog.ProvisioningSchemeId)
    {
        Write-Log "Given catalog [$MachineCatalogName] does not have an associated provisioning scheme." -DgName $dgName
        return $false;
    }

    # Provisioning Scheme
    $provScheme = Get-ProvScheme -ProvisioningSchemeUid ($catalog.ProvisioningSchemeId)

    if ($null -eq $provScheme.IdentityPoolUid)
    {
        Write-Log "Associated provisioning scheme [($provScheme.ProvisioningSchemeUid)] does not have an associated Identity Pool." -DgName $dgName
        return $false;
    }

    # Identity Pool
    $identityPool = Get-AcctIdentityPool -IdentityPoolUid ($provScheme.IdentityPoolUid)
    if ($null -eq $identityPool.NamingScheme)
    {
        Write-Log "Associated identity pool [$IdentityPoolUid] does not have a corresponding NamingScheme." -DgName $dgName
        return $false
    }

    # Script Tag
    $tagExists = @(Get-BrokerTag | Where-Object { $_.Name -eq $ScriptTag}).Count -gt 0
    if ($tagExists)
    {
        Write-Log "Warning... tag [$ScriptTag] is already in use, machines marked with this tag could cause the Autoscale Machine Creation script to delete more machines than it created." -DgName $dgName
    }

    return $true
}

function Edit-Watermarks
{
    param([object]$DeliveryGroup)

    if ($LowWatermark -le 0)
    {
        throw "[$($DeliveryGroup.Name)]: HighWatermark cannot be set without also setting the LowWatermark"
    }

    if ($HighWatermark -le 0)
    {
        throw "[$($DeliveryGroup.Name)]: LowWatermark cannot be set without also setting the HighWatermark"
    }

    if ($LowWatermark -ge $HighWatermark)
    {
        throw "[$($DeliveryGroup.Name)]: LowWatermark [$LowWatermark] can not be set to a higher value than HighWatermark [$HighWatermark]"
    }

    # Update stored watermarks
    $map = @{ `
        ($AutoscaleMetadataNames['LowWatermark']) = [string]($LowWatermark); `
        ($AutoscaleMetadataNames['HighWatermark']) = [string]($HighWatermark); `
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
}

function Edit-MaximumCreatedMachines
{
    param([object]$DeliveryGroup)

    # Update Maximum Created Machines
    $map = @{ `
        ($AutoscaleMetadataNames['MaximumCreatedMachines']) = [string]($MaximumCreatedMachines);  `
    }

    $DeliveryGroup | Set-BrokerDesktopGroupMetadata -Map $map
}

function Write-Log 
{
    param(
        [String]$Event,
        [String]$DgName = $null,
        [bool]$Trivial = $false
    )

    if ($DgName)
    {
        $message = "[$DgName]: $Event"
    } else {
        $message = "Common Log: $Event"
    }

    if ($Trivial)
    {
        # Trivial should not be printed (unless debug output is needed)
        Write-Debug $message
        return
    }

    if ($EventLogSource)
    {
        Write-EventLog -LogName Application -Source $EventLogSource -Message $message -EventId 1
        return
    }

    Write-Host $message
}

function Get-CurrentTimeString
{
    return [string] (Get-Date -UFormat "%Y/%m/%d %H:%M:%S");
}

# ============================================================================
# Main
# ============================================================================

# Stop whenever an error is hit
$ErrorActionPreference = 'Stop'
Add-PSSnapIn Citrix.*

# Load XD Credentials Profile
Set-XDCredentials -ProfileName $XdProfileName

# Extract Delivery Groups
$dgNames = $DeliveryGroupName.Split(';')

ForEach ($name in $dgNames)
{
    try {
        $dg = Get-BrokerDesktopGroup -Name $name
        if ($null -eq $dg)
        {
            Write-Log "Could not retrieve delivery group with name [$name]"
            continue
        }
        
        if ($dg -is [System.Array])
        {
            Write-Log "Cannot use [$name] (wildcards\empty) to retrieve more than one desktop group."
            continue
        }

        $state = $dg.MetadataMap[$AutoscaleMetadataNames['State']]
        if ($null -eq $state)
        {
            # Enforce restriction (Initialization\Update of Delivery Group can only occur if there is exactly one delivery group)
            if ($dgNames.Length -ne 1)
            {
                Write-Log "Cannot update the watermarks or Machine Catalogs for more than one delivery group at a time"
                break
            }

            $state = Initialize-StateMachine $dg

            # Reload Delivery Group after initialization
            $dg = Get-BrokerDesktopGroup -Uid $dg.Uid
        }
        else
        {
            $state = [AutoscaleScriptState]$state
        }

        if (($LowWatermark -ge 0) -or ($HighWatermark -ge 0))
        {
            # Enforce restriction (Initialization\Update of Delivery Group can only occur if there is exactly one delivery group)
            if ($dgNames.Length -ne 1)
            {
                Write-Log "Cannot update the watermarks or Machine Catalogs for more than one delivery group at a time"
                break
            }

            # Update the watermarks in the delivery group
            Edit-Watermarks $dg

            # Reload Delivery Group after editing watermarks
            $dg = Get-BrokerDesktopGroup -Uid $dg.Uid
        }

        if ($MaximumCreatedMachines -ge 0)
        {
            # Enforce restriction (Initialization\Update of Delivery Group can only occur if there is exactly one delivery group)
            if ($dgNames.Length -ne 1)
            {
                Write-Log "Cannot update the MaximumCreatedMachines more than one delivery group at a time"
                break
            }

            # Update MaximumCreatedMachines
            Edit-MaximumCreatedMachines $dg

            # Reload Delivery Group after editing MaximumCreatedMachines
            $dg = Get-BrokerDesktopGroup -Uid $dg.Uid
        }

        if ($EventLogSource)
        {
            # Update EventLogSource
            $dg | Set-BrokerDesktopGroupMetadata -Name $AutoscaleMetadataNames['EventLogSource'] -Value $EventLogSource
        }
        else
        {
            # Load EventLogSource
            $EventLogSource = $dg.MetadataMap[$AutoscaleMetadataNames['EventLogSource']]
        }

        Resume-AutoscaleStateMachine $state $dg
    } catch
    {
        Write-Log "While processing [$name] encountered error: $_"
    }
}
