<#
.SYNOPSIS
  Orchestrator: run stages 1–5 (low risk) interactively, then prompt about 6–8.
.PARAMETER YesAll
  Skip confirmation prompts for stages 1, 3, and 4 (low risk).
#>
[CmdletBinding()]
param(
    [switch]$YesAll
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

$report = Join-Path $PSScriptRoot 'Get-DiskReport.ps1'
$stage1 = Join-Path $PSScriptRoot 'Invoke-Stage1-TempClean.ps1'
$stage2 = Join-Path $PSScriptRoot 'Invoke-Stage2-HiberPagefile.ps1'
$stage3 = Join-Path $PSScriptRoot 'Invoke-Stage3-DismCleanup.ps1'
$stage4 = Join-Path $PSScriptRoot 'Invoke-Stage4-UwpBloat.ps1'
$stage5 = Join-Path $PSScriptRoot 'Invoke-Stage5-MoveApps.ps1'

Write-Section "win-c-cleaner: 全流程编排"
& $report
$startFree = Get-FreeSpaceGB

# --- Stage 1 ---
if ($YesAll -or (Confirm-Step '执行阶段 1：临时文件清理？')) {
    & $stage1 -Execute
}

# --- Stage 2 (always ask) ---
Write-Host ""
if (Confirm-Step '执行阶段 2：关休眠 / 缩 pagefile？（会问每个子项）') {
    $opts = @()
    if (Confirm-Step '  - 关闭休眠 (powercfg /h off)？') { $opts += '-DisableHibernation' }
    if (Confirm-Step '  - 固定 pagefile 大小？')         { $opts += '-ShrinkPagefile' }
    if ($opts) {
        & $stage2 @opts
    }
}

# --- Stage 3 ---
Write-Host ""
if ($YesAll -or (Confirm-Step '执行阶段 3：DISM WinSxS 清理？')) {
    $resetBase = Confirm-Step '  使用 /ResetBase？（不可逆，之后无法卸载更新）'
    if ($resetBase) { & $stage3 -ResetBase } else { & $stage3 }
}

# --- Stage 4 ---
Write-Host ""
if ($YesAll -or (Confirm-Step '执行阶段 4：卸载 UWP 垃圾应用？')) {
    $aggr = Confirm-Step '  使用扩展列表 (-AggressiveList)？'
    if ($aggr) { & $stage4 -AggressiveList } else { & $stage4 }
}

# --- Stage 5 ---
Write-Host ""
if (Confirm-Step '执行阶段 5：列出可移动的大型 UWP 应用？') {
    & $stage5
}

# --- Final report ---
$endFree = Get-FreeSpaceGB
Write-Section "执行结果"
Write-Host ("Before {0} GB → After {1} GB （释放 {2:N2} GB）" -f $startFree, $endFree, ($endFree - $startFree)) -ForegroundColor Green

Write-Host ""
Write-Host "下一步（不在本编排里，需要单独运行）：" -ForegroundColor Yellow
Write-Host "  阶段 6 - 重复驱动:  Get-DuplicateDrivers.ps1; Invoke-Stage6-DriverCleanup.ps1 -Batch Display -Execute"
Write-Host "  阶段 7 - OEM 软件:  Invoke-Stage7-OemBloat.ps1"
Write-Host "  阶段 8 - OEM ppkg:  Invoke-Stage8-RemovePpkg.ps1 -BackupDir D:\Backup-OEM-ppkg"
Write-Host ""
Write-Host "⚠️  阶段 2 关休眠/改 pagefile，以及阶段 3 DISM 需要重启才能完全释放空间。" -ForegroundColor Yellow
