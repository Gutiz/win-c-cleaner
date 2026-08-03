<#
.SYNOPSIS
  System drive baseline report: total / used / free, top folders, key bloat files.
.EXAMPLE
  .\Get-DiskReport.ps1
#>
[CmdletBinding()]
param(
    [string]$Drive = $env:SystemDrive.TrimEnd('\'),
    [int]$TopN = 15
)

. "$PSScriptRoot\_Common.ps1"
Assert-Windows10Plus

Write-Section "磁盘报告 - $Drive"

$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
$total = [math]::Round($d.Size / 1GB, 2)
$free  = [math]::Round($d.FreeSpace / 1GB, 2)
$used  = [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
$pct   = [math]::Round(($d.Size - $d.FreeSpace) / $d.Size * 100, 1)

[PSCustomObject]@{
    Drive     = $Drive
    TotalGB   = $total
    UsedGB    = $used
    FreeGB    = $free
    UsedPct   = "$pct%"
} | Format-Table -AutoSize

Write-Host "已知大户文件:" -ForegroundColor Yellow
$candidates = @(
    "$Drive\hiberfil.sys",
    "$Drive\pagefile.sys",
    "$Drive\swapfile.sys",
    "$Drive\Windows\MEMORY.DMP"
)
foreach ($p in $candidates) {
    # Test-Path/Get-Item report kernel-locked files (hiberfil, pagefile,
    # swapfile) as missing; Get-SystemFileInfo enumerates the parent instead.
    $item = Get-SystemFileInfo -Path $p
    if ($item) {
        "  {0,-35} {1}" -f $p, (Format-GB $item.Length) | Write-Host
    }
}

Write-Host ""
Write-Host "WinSxS 组件存储分析 (可能较慢, 10-30s)..." -ForegroundColor Yellow
try {
    # Decode DISM with the OEM code page, otherwise the localized keywords below
    # never match and this section prints nothing.
    $dism = Invoke-NativeOem { Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 } | Out-String
    ($dism -split "`r?`n" | Where-Object { $_ -match 'Component Store|Actual Size|Reclaimable|组件存储|实际大小|可回收|推荐' }) |
        ForEach-Object { "  $_" } | Write-Host
} catch {
    Write-Host "  (DISM 分析失败: $_)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "C 盘根目录 Top $TopN 大文件夹:" -ForegroundColor Yellow
Get-ChildItem -LiteralPath "$Drive\" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Folder  = $_.FullName
        SizeGB  = [math]::Round((Get-FolderSize -Path $_.FullName) / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending | Select-Object -First $TopN | Format-Table -AutoSize

Write-Host ""
Write-Host "可用空间: $free GB / $total GB" -ForegroundColor Green
