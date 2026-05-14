<#
.SYNOPSIS
  Stage 4: uninstall low-value preinstalled UWP packages.
.PARAMETER AggressiveList
  Also remove the "ask first" list (YourPhone, communications apps, Bing*, Xbox, Solitaire).
.PARAMETER DryRun
  Just list matches, do not uninstall.
.PARAMETER AllUsers
  Pass -AllUsers to Remove-AppxPackage (requires admin).
#>
[CmdletBinding()]
param(
    [switch]$AggressiveList,
    [switch]$DryRun,
    [switch]$AllUsers
)

. "$PSScriptRoot\_Common.ps1"
if ($AllUsers) { Assert-Admin }
Assert-Windows10Plus

Write-Section "阶段 4：卸载 UWP 垃圾应用"

$recommended = @(
    '*PCManager*',          # 微软电脑管家
    '*MSPCManager*',
    '*Timeline*',           # 时间线（已弃用）
    '*WebExperience*',      # Win11 小组件
    '*GetHelp*',
    '*DevHome*',
    '*IntelArcSoftware*',   # 核显机型不需要
    '*ZuneVideo*'           # 电影和电视
)

$aggressive = @(
    '*YourPhone*', '*CrossDevice*',
    '*communicationsapps*',
    '*BingNews*', '*BingWeather*',
    '*MicrosoftSolitaireCollection*',
    '*Xbox*',
    '*OfficeHub*',
    '*Microsoft3DViewer*',
    '*MixedReality.Portal*',
    '*MicrosoftStickyNotes*',
    '*Microsoft.Wallet*',
    '*Print3D*'
)

$patterns = if ($AggressiveList) { $recommended + $aggressive } else { $recommended }

Write-Host "扫描匹配的 UWP 包..."
$matched = foreach ($p in $patterns) {
    Get-AppxPackage -Name $p -ErrorAction SilentlyContinue
    if ($AllUsers) { Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue }
}
$matched = $matched | Sort-Object Name -Unique

if (-not $matched) {
    Write-Host "未匹配到任何包。" -ForegroundColor Green
    return
}

$matched | Select-Object Name, PackageFullName | Format-Table -AutoSize

if ($DryRun) {
    Write-Host "DRY-RUN：未卸载。加 -DryRun:`$false 执行。" -ForegroundColor Yellow
    return
}

if (-not (Confirm-Step "确认卸载以上 $($matched.Count) 个包？")) { return }

foreach ($pkg in $matched) {
    try {
        if ($AllUsers) {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
        } else {
            Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        }
        Write-Host "  [ok] $($pkg.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [fail] $($pkg.Name): $_" -ForegroundColor Yellow
    }
}
