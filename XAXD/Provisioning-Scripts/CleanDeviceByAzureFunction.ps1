# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format.
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

function GetGrapgAccessTokenByFunctionManagedIdentity{
    $GraphToken = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/"
    return $GraphToken.token
}

function CleanStaleDeviceRecordFromAureADAndMSEndpoint([string]$NamingScheme, [string]$GraphToken)
{
    if ([string]::IsNullOrEmpty($NamingScheme) -eq $true)
    {
        Write-Host "NamingScheme parameter is required."
        return
    }

    if(-not $NamingScheme.Contains('#'))
    {
        Write-Host "NamingScheme must contain '#', please check NamingScheme format."
        return
    }

    $StartIndex = $NamingScheme.IndexOf('#')
    $EndIndex = $NamingScheme.LastIndexOf('#')
    $MaskLength = $EndIndex - $StartIndex + 1

    $NameSchemePrefix = $NamingScheme.Substring(0,$startIndex)
    $NamingSchemeSuffix = $NamingScheme.Substring($EndIndex + 1)

    $NamingSchemeReg = "^$($NameSchemePrefix)[A-Z,0-9]{$($MaskLength)}$($NamingSchemeSuffix)$"

    Write-Host "Start to filter AzureAD Devices by $($NamingScheme)..."

    $headers = @{
            "Authorization" = "Bearer $GraphToken"
            "Content-type"  = "application/json"
        }

    $AzureADDevicesUrl = "https://graph.microsoft.com/v1.0/devices"
    $AzureADMatchedDevices = @()
    $DevicesResponse = (Invoke-RestMethod -Uri $AzureADDevicesUrl -Headers $headers -Method Get)
    $Devices = $DevicesResponse.value
    $DevicesNextLink = $DevicesResponse."@odata.nextLink"
    while ($null -ne $DevicesNextLink)
    {
        $DevicesResponse = (Invoke-RestMethod -Uri $DevicesNextLink -Headers $headers -Method Get)
        $DevicesNextLink = $DevicesResponse."@odata.nextLink"
        $Devices += $DevicesResponse.value
    }
    $AzureADMatchedDevices = $Devices | Where{$_.displayName -match $NamingSchemeReg}

    $DevicesToRemove = @()
    $VirtualMachines = Get-AzVM 
    foreach($device in $AzureADMatchedDevices)
    {
        $vmFound = $VirtualMachines | Where{$_.Name -match $device.displayName}
        $Row = $device | Select Type, Name, Id, DateTime
        $Row.Type = "AAD"
        $Row.Name = $device.displayName
        $Row.Id = $device.id

        if($Device.registrationDateTime){
            $Row.DateTime = [Datetime]$Device.registrationDateTime
        }else{
            $Row.DateTime = $null
        }

        # If VM doesn't exist in Azure, then can clean the Azure AD device record.
        if($null -eq $vmFound)
        {
            $DevicesToRemove += $Row
        }
    }

    $AzureADDeviceToRemove = $DevicesToRemove | Select Name
    if($CleanIntuneDevice){
        $MDMDevicesUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices"
        $MDMMatchedDevices = (Invoke-RestMethod -Headers $headers -Uri $MDMDevicesUrl -Method GET).value | Where{$_.deviceName -match $NamingSchemeReg}

        foreach($MDMMatchedDevice in $MDMMatchedDevices)
        {
            if($AzureADDeviceToRemove.Name -Contains $MDMMatchedDevice.deviceName)
            {
                $Row = "" | Select Type, Name, Id, DateTime
                $Row.Type = "MDM"
                $Row.Name = $MDMMatchedDevice.deviceName
                $Row.Id = $MDMMatchedDevice.id
                $Row.DateTime = [Datetime]$MDMMatchedDevice.enrolledDateTime
                $DevicesToRemove += $Row
            }
        }
    }    

    if ($DevicesToRemove.Length -eq 0)
    {
        Write-Host "No devices need removal."
        return
    }

    Write-Host "`nThese devices will be removed from AzureAD Devices:"
    $DevicesToRemove.ForEach({Write-Host "Type: $($_.Type) Name: $($_.Name), ObjectId: $($_.Id), DateTime: $($_.DateTime)"})

    # Delete the stale device with graph API
    $DevicesToRemove.ForEach({
        Write-Host "Deleting devices: Type: $($_.Type) Name: $($_.Name), ObjectId: $($_.Id), DateTime: $($_.DateTime)"
        $DeleteDeviceUrl = ''
        if ($_.Type -eq "AAD")
        {
            $DeleteDeviceUrl = "https://graph.microsoft.com/v1.0/devices/$($_.Id)"
        }
        else
        {
            $DeleteDeviceUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($_.Id)"
        }
        $response = (Invoke-RestMethod -Headers $headers -Uri $DeleteDeviceUrl -Method DELETE).value
    })

    Write-Host "Clean up $($DevicesToRemove.Count) stale devices."
}

$CleanIntuneDevice = $False # Set it to be $True if want to clean Azure AD device's record in Intune.
$NamingScheme = "ABCD#" # The naming scheme should be between 2 and 15 characters
$GraphToken = GetGrapgAccessTokenByFunctionManagedIdentity
CleanStaleDeviceRecordFromAureADAndMSEndpoint $NamingScheme $GraphToken
