<#
.SYNOPSIS
  Stage 1: Temp/cache cleanup (low risk).
.PARAMETER Execute
  Without it, runs in dry-run mode showing what would be freed.
.PARAMETER SkipWindowsUpdate
  Skip stopping wuauserv + clearing SoftwareDistribution\Download.
#>
[CmdletBinding()]
param(
    [switch]$Execute,
    [switch]$SkipWindowsUpdate
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

$dryRun = -not $Execute
Write-Section ("阶段 1：临时文件 / 缓存清理 " + $(if ($dryRun) {'[DRY-RUN]'} else {'[EXECUTE]'}))

$before = Get-FreeSpaceGB
Write-Host "Before: $before GB free" -ForegroundColor Green

$targets = @(
    'C:\Windows\Temp',
    $env:TEMP,
    "$env:LOCALAPPDATA\Temp",
    'C:\Windows\Prefetch',
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",   # thumbcache; only *.db cleared below
    'C:\ProgramData\Microsoft\Windows\WER\ReportQueue',
    'C:\ProgramData\Microsoft\Windows\WER\ReportArchive',
    'C:\Windows\Minidump',
    'C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache'
)

# Windows Update download cache (needs wuauserv stopped)
if (-not $SkipWindowsUpdate) {
    Write-Host "`n[1/3] 停 Windows Update 服务清下载缓存"
    if (-not $dryRun) {
        Stop-Service wuauserv,bits -Force -ErrorAction SilentlyContinue
    }
    [void](Remove-SafeContents -Path 'C:\Windows\SoftwareDistribution\Download' -WhatIf:$dryRun)
    if (-not $dryRun) {
        Start-Service wuauserv,bits -ErrorAction SilentlyContinue
    }
}

Write-Host "`n[2/3] 清理临时目录"
foreach ($t in $targets) {
    if ($t -like "*Explorer*") {
        # only thumbnail/icon cache db files
        if (-not $dryRun -and (Test-Path -LiteralPath $t)) {
            Get-ChildItem -LiteralPath $t -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $t -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "    [ok] $t (thumbcache_*.db, iconcache_*.db)" -ForegroundColor Green
        } else {
            Write-Host "    [dry-run] $t (thumbcache_*.db)" -ForegroundColor Yellow
        }
        continue
    }
    [void](Remove-SafeContents -Path $t -WhatIf:$dryRun)
}

# MEMORY.DMP
$memDump = 'C:\Windows\MEMORY.DMP'
if (Test-Path -LiteralPath $memDump) {
    $size = (Get-Item -LiteralPath $memDump -Force).Length
    if ($dryRun) {
        Write-Host ("    [dry-run] {0}  ({1})" -f $memDump, (Format-GB $size)) -ForegroundColor Yellow
    } else {
        Remove-Item -LiteralPath $memDump -Force -ErrorAction SilentlyContinue
        Write-Host ("    [ok] {0}  释放 {1}" -f $memDump, (Format-GB $size)) -ForegroundColor Green
    }
}

Write-Host "`n[3/3] 清空回收站"
if (-not $dryRun) {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Host "    [ok] 回收站已清空" -ForegroundColor Green
} else {
    Write-Host "    [dry-run] Clear-RecycleBin -Force" -ForegroundColor Yellow
}

$after = Get-FreeSpaceGB
Write-Host ""
Write-Host ("Before {0} GB → After {1} GB （释放 {2:N2} GB）" -f $before, $after, ($after - $before)) -ForegroundColor Cyan

if ($dryRun) {
    Write-Host "`n这是预演。加 -Execute 真实执行。" -ForegroundColor Yellow
}
