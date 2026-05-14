<#
.SYNOPSIS
  Stage 2: disable hibernation and/or shrink the pagefile.
.PARAMETER DisableHibernation
  Run `powercfg /h off` (frees hiberfil.sys, ~= RAM size).
.PARAMETER ShrinkPagefile
  Set C: pagefile to fixed InitialMB/MaximumMB. Default 2048/4096.
.PARAMETER InitialMB
.PARAMETER MaximumMB
.EXAMPLE
  .\Invoke-Stage2-HiberPagefile.ps1 -DisableHibernation
.EXAMPLE
  .\Invoke-Stage2-HiberPagefile.ps1 -ShrinkPagefile -InitialMB 2048 -MaximumMB 4096
#>
[CmdletBinding()]
param(
    [switch]$DisableHibernation,
    [switch]$ShrinkPagefile,
    [int]$InitialMB = 2048,
    [int]$MaximumMB = 4096
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

Write-Section "阶段 2：关休眠 + 缩虚拟内存"

$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Host "系统内存: $ramGB GB"

if (-not $DisableHibernation -and -not $ShrinkPagefile) {
    Write-Host ""
    Write-Host "请选择子项，不会自动执行：" -ForegroundColor Yellow
    Write-Host "  -DisableHibernation         关闭休眠（释放 hiberfil.sys，约 ${ramGB} GB）"
    Write-Host "  -ShrinkPagefile             固定 pagefile 大小（建议仅在 RAM >= 16 GB 时使用）"
    Write-Host "  -ShrinkPagefile -InitialMB <n> -MaximumMB <n>"
    return
}

if ($DisableHibernation) {
    $hiber = 'C:\hiberfil.sys'
    if (Test-Path -LiteralPath $hiber) {
        $sz = (Get-Item -LiteralPath $hiber -Force).Length
        Write-Host ("当前 hiberfil.sys: {0}" -f (Format-GB $sz))
    }
    if (Confirm-Step '确认关闭休眠？(Fast Startup 也会失效)') {
        powercfg /h off
        Write-Host "[ok] powercfg /h off 已执行（重启后 hiberfil.sys 完全释放）" -ForegroundColor Green
    } else {
        Write-Host "[skip] 保留休眠" -ForegroundColor DarkGray
    }
}

if ($ShrinkPagefile) {
    if ($ramGB -lt 16) {
        Write-Host "[警告] RAM 仅 $ramGB GB，固定 pagefile 可能导致大型程序/编译失败。" -ForegroundColor Yellow
        if (-not (Confirm-Step '确认继续缩小 pagefile？')) { return }
    }

    Write-Host "备份当前 pagefile 设置到 $PSScriptRoot\pagefile-backup.txt"
    Get-CimInstance Win32_ComputerSystem | Select-Object AutomaticManagedPagefile |
        Out-File -FilePath (Join-Path $PSScriptRoot 'pagefile-backup.txt') -Encoding UTF8
    Get-CimInstance Win32_PageFileSetting |
        Out-File -FilePath (Join-Path $PSScriptRoot 'pagefile-backup.txt') -Append -Encoding UTF8

    if (Confirm-Step "确认把 C: pagefile 改为 Initial=${InitialMB}MB / Max=${MaximumMB}MB？") {
        # 关闭自动管理
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.AutomaticManagedPagefile) {
            Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
            Write-Host "[ok] 已关闭 AutomaticManagedPagefile" -ForegroundColor Green
        }
        $pf = Get-CimInstance Win32_PageFileSetting -Filter "Name='C:\\\\pagefile.sys'"
        if ($pf) {
            Set-CimInstance -InputObject $pf -Property @{ InitialSize = $InitialMB; MaximumSize = $MaximumMB }
        } else {
            New-CimInstance -ClassName Win32_PageFileSetting -Property @{
                Name = 'C:\pagefile.sys'; InitialSize = $InitialMB; MaximumSize = $MaximumMB
            } | Out-Null
        }
        Write-Host "[ok] pagefile 设置已更新，重启后生效" -ForegroundColor Green
        Write-Host "    回滚: Set-CimInstance Win32_ComputerSystem -Property @{AutomaticManagedPagefile=`$true}" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "⚠️  本阶段需要重启才能完全生效。" -ForegroundColor Yellow
