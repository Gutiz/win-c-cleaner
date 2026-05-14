<#
.SYNOPSIS
  Stage 3: DISM component store cleanup.
.PARAMETER ResetBase
  Also remove ability to uninstall previously installed updates. IRREVERSIBLE.
#>
[CmdletBinding()]
param(
    [switch]$ResetBase
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

Write-Section "阶段 3：DISM 清理 WinSxS"
$before = Get-FreeSpaceGB
Write-Host "Before: $before GB free"

Write-Host "`n[1/2] 分析组件存储 (可能 10-30s)..."
& Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore | ForEach-Object { "  $_" }

Write-Host "`n[2/2] 执行组件清理 (可能 10-20 分钟)..."
if ($ResetBase) {
    Write-Host "[警告] 使用 /ResetBase ：清理后将无法卸载之前已安装的更新。" -ForegroundColor Yellow
    if (-not (Confirm-Step '确认使用 /ResetBase？')) { exit 0 }
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
} else {
    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup
}

$after = Get-FreeSpaceGB
Write-Host ""
Write-Host ("Before {0} GB → After {1} GB （释放 {2:N2} GB，重启后会进一步释放）" -f $before, $after, ($after - $before)) -ForegroundColor Cyan
Write-Host "⚠️  完整生效需要重启。" -ForegroundColor Yellow
