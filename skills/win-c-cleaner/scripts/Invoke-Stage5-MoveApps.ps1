<#
.SYNOPSIS
  Stage 5: list large UWP apps on C: that can be moved to another drive,
  then open the "Installed apps" settings page for the user to click Move.

  UWP app relocation has no PowerShell API; the actual move must be triggered
  from the Settings UI (`ms-settings:appsfeatures`).
.PARAMETER MinMB
  Minimum install size to list (default 200 MB).
.PARAMETER TargetDrive
  Optional informational drive label to suggest (e.g. 'D:').
#>
[CmdletBinding()]
param(
    [int]$MinMB = 200,
    [string]$TargetDrive
)

. "$PSScriptRoot\_Common.ps1"
Assert-Windows10Plus

Write-Section "阶段 5：移动大型 UWP 应用"

Write-Host "扫描 C 盘上 >= ${MinMB} MB 的 UWP 应用..."

$sysDrive = Get-SystemDrive
$rows = Get-AppxPackage | ForEach-Object {
    $loc = $_.InstallLocation
    if (-not $loc) { return }
    if (-not $loc.StartsWith($sysDrive, [StringComparison]::OrdinalIgnoreCase)) { return }
    $size = (Get-ChildItem -LiteralPath $loc -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum
    if (-not $size) { return }
    if (($size / 1MB) -lt $MinMB) { return }
    [PSCustomObject]@{
        Name    = $_.Name
        SizeMB  = [math]::Round($size / 1MB, 1)
        InstallLocation = $loc
    }
}
$rows = $rows | Sort-Object SizeMB -Descending

if (-not $rows) {
    Write-Host "没有匹配的应用。" -ForegroundColor Green
    return
}

$rows | Format-Table -AutoSize

Write-Host ""
Write-Host "操作方法：" -ForegroundColor Yellow
Write-Host "  1. 即将打开「已安装的应用」设置页"
Write-Host "  2. 找到上面列出的应用 → 右侧 ⋯ → 移动 → 选目标盘$(if($TargetDrive) { ` (建议 $TargetDrive)`})"
Write-Host "  3. 若没有「移动」按钮，说明该应用是预装或不支持迁移"
Write-Host ""
Write-Host "可选：把以后新装的应用默认装到其他盘："
Write-Host "  设置 → 系统 → 存储 → 高级存储设置 → 保存新内容的位置"
Write-Host ""

if (Confirm-Step '现在打开「已安装的应用」？') {
    Start-Process 'ms-settings:appsfeatures'
}
