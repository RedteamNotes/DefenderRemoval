<#
.SYNOPSIS
    彻底禁用 Windows Defender 相关组件。
.DESCRIPTION
    此脚本通过修改注册表、服务配置及排除策略，强制终止 Defender 运行。
#>

[CmdletBinding()]
param (
    [Parameter()]
    [Switch]$PurgeFiles
)

# 1. 权限检查
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Write-Error "操作失败：需要提升至管理员权限。"
    return
}

# 2. 预检：篡改防护 (Tamper Protection)
# 注意：此开关受系统内核保护，无法通过脚本远程关闭。
$TamperKey = "HKLM:\SOFTWARE\Microsoft\Windows Defender\Features"
$Status = Get-ItemProperty -Path $TamperKey -Name "TamperProtection" -ErrorAction SilentlyContinue
if ($Status.TamperProtection -ne 4) {
    Write-Warning "检测到篡改防护可能处于开启状态，请先手动关闭以确保脚本生效。"
}

# 3. 注入全盘排除策略
Write-Host "[1/4] 正在配置全盘扫描排除..."
$Drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
foreach ($Drive in $Drives) {
    Add-MpPreference -ExclusionPath $Drive -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "$($Drive)*" -ErrorAction SilentlyContinue
}

# 4. 停用扫描引擎与监控
Write-Host "[2/4] 正在停用实时监控与扫描引擎..."
$Config = @{
    DisableRealtimeMonitoring = $true
    DisableBehaviorMonitoring = $true
    DisableIOAVProtection = $true
    DisableScriptScanning = $true
    MAPSReporting = 0
    SubmitSamplesConsent = 0
}
Set-MpPreference @Config -ErrorAction SilentlyContinue

# 5. 修改服务启动类型
Write-Host "[3/4] 正在封锁核心服务与内核驱动..."
$ComponentList = @(
    "WinDefend", "WdNisSvc", "Sense", "SecurityHealthService", # Services
    "WdBoot", "WdFilter", "WdNisDrv"                          # Drivers
)

foreach ($Comp in $ComponentList) {
    $Path = "HKLM:\SYSTEM\CurrentControlSet\Services\$Comp"
    if (Test-Path $Path) {
        Set-ItemProperty -Path $Path -Name "Start" -Value 4
    }
}

# 6. 物理组件清理
if ($PurgeFiles) {
    Write-Host "[4/4] 正在清理物理二进制文件..."
    $TargetDir = "C:\ProgramData\Microsoft\Windows Defender"
    takeown /f $TargetDir /r /d y | Out-Null
    icacls $TargetDir /grant administrators:F /t | Out-Null
    Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[!] 操作完成。系统重启后 Defender 将停止工作。" -ForegroundColor Green