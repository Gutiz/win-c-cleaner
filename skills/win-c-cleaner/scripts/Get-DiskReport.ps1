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
    if (Test-Path -LiteralPath $p) {
        $item = Get-Item -LiteralPath $p -Force
        "  {0,-35} {1}" -f $p, (Format-GB $item.Length) | Write-Host
    }
}

Write-Host ""
Write-Host "WinSxS 组件存储分析 (可能较慢, 10-30s)..." -ForegroundColor Yellow
try {
    $dism = & Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1 | Out-String
    ($dism -split "`r?`n" | Where-Object { $_ -match 'Component Store|Actual Size|Reclaimable|组件存储|实际大小|可回收' }) |
        ForEach-Object { "  $_" } | Write-Host
} catch {
    Write-Host "  (DISM 分析失败: $_)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "C 盘根目录 Top $TopN 大文件夹:" -ForegroundColor Yellow
Get-ChildItem -LiteralPath "$Drive\" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum
    [PSCustomObject]@{
        Folder  = $_.FullName
        SizeGB  = [math]::Round(($size | ForEach-Object { if ($_) { $_ } else { 0 } }) / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending | Select-Object -First $TopN | Format-Table -AutoSize

Write-Host ""
Write-Host "可用空间: $free GB / $total GB" -ForegroundColor Green
