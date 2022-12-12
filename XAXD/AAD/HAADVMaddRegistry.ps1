$VirtualDesktopKeyPath = 'HKLM:\Software\AzureAD\VirtualDesktop'
$WorkplaceJoinKeyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WorkplaceJoin'
$MaxCount = 60

for ($count = 1; $count -le $MaxCount; $count++)
{
    if ((Test-Path -Path $VirtualDesktopKeyPath) -eq $true)
    {
        $provider = (Get-Item -Path $VirtualDesktopKeyPath).GetValue("Provider", $null)
        if ($provider -eq 'Citrix')
        {
            break;
        }

        if ($provider -eq 1)
        {
            Set-ItemProperty -Path $VirtualDesktopKeyPath -Name "Provider" -Value "Citrix" -Force
            Set-ItemProperty -Path $WorkplaceJoinKeyPath -Name "autoWorkplaceJoin" -Value 1 -Force
            Start-Sleep 5
            dsregcmd /join
            break
        }
    }

    Start-Sleep 1
}


