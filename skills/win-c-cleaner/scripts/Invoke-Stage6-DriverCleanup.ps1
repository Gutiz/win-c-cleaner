<#
.SYNOPSIS
  Stage 6: delete duplicate old drivers from DriverStore in batches.
.DESCRIPTION
  Reads delete-old-drivers.ps1 produced by Get-DuplicateDrivers.ps1, enables
  the lines matching the chosen batch (display / bluetooth / rest), then runs.
  Always re-saves the script first so the user can review.
.PARAMETER ScriptPath
  Path to delete-old-drivers.ps1.
.PARAMETER Batch
  Which group to enable: Display | Bluetooth | Rest.
.PARAMETER Execute
  Without -Execute, only previews enabled lines.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [Parameter(Mandatory)][ValidateSet('Display','Bluetooth','Rest')][string]$Batch,
    [switch]$Execute
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

if (-not (Test-Path -LiteralPath $ScriptPath)) {
    Write-Host "[ERROR] 找不到 $ScriptPath。请先运行 Get-DuplicateDrivers.ps1。" -ForegroundColor Red
    exit 1
}

$displayPatterns   = 'iigd_ext\.inf|igdkmd[^.]*\.inf|cui_dch\.inf|igcc_dch\.inf|mshdadac\.inf|nv[a-z]+\.inf|atikmdag\.inf|amdkmdag\.inf|amdkmpfd\.inf'
$bluetoothPatterns = 'ibtusb\.inf|btha[^.]*\.inf|bth[^.]*\.inf'
$pattern = switch ($Batch) {
    'Display'   { $displayPatterns }
    'Bluetooth' { $bluetoothPatterns }
    'Rest'      { $null }   # everything that wasn't display/bluetooth
}

$lines = Get-Content -LiteralPath $ScriptPath
$enabled = @()
$prevInfLine = ''
$newLines = foreach ($line in $lines) {
    if ($line -match '^\s*#\s*([\w\-]+\.inf)\s+keep') {
        $prevInfLine = $line
        $line
        continue
    }
    if ($line -match '^\s*#\s*pnputil ') {
        $infName = if ($prevInfLine -match '#\s*([\w\-]+\.inf)') { $Matches[1] } else { '' }
        $shouldEnable = switch ($Batch) {
            'Display'   { $infName -match $displayPatterns }
            'Bluetooth' { $infName -match $bluetoothPatterns }
            'Rest'      { ($infName -notmatch $displayPatterns) -and ($infName -notmatch $bluetoothPatterns) }
        }
        if ($shouldEnable) {
            $clean = $line -replace '^\s*#\s*',''
            $enabled += $clean
            $clean
        } else {
            $line
        }
        continue
    }
    $line
}

$newLines | Set-Content -LiteralPath $ScriptPath -Encoding UTF8

Write-Host "批次: $Batch" -ForegroundColor Cyan
Write-Host "启用的命令数: $($enabled.Count)"
$enabled | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

if (-not $enabled) {
    Write-Host "该批次无匹配，未执行。" -ForegroundColor Yellow
    return
}

if (-not $Execute) {
    Write-Host ""
    Write-Host "预览完成。确认无误后加 -Execute 真正执行：" -ForegroundColor Yellow
    Write-Host "  .\Invoke-Stage6-DriverCleanup.ps1 -ScriptPath '$ScriptPath' -Batch $Batch -Execute"
    return
}

if (-not (Confirm-Step "确认对 $($enabled.Count) 个旧驱动执行 pnputil /delete-driver /force ？")) { return }

$before = Get-FreeSpaceGB
& $ScriptPath
$after = Get-FreeSpaceGB
Write-Host ""
Write-Host ("Before {0} GB → After {1} GB （释放 {2:N2} GB）" -f $before, $after, ($after - $before)) -ForegroundColor Cyan
Write-Host "⚠️  强烈建议重启并验证对应硬件正常工作后再处理下一批。" -ForegroundColor Yellow
