# Shared helpers for win-c-cleaner stage scripts.
# Dot-source: . "$PSScriptRoot\_Common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Admin {
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host '[ERROR] 需要管理员 PowerShell。请右键 PowerShell -> 以管理员身份运行。' -ForegroundColor Red
        exit 1
    }
}

function Assert-Windows10Plus {
    $os = Get-CimInstance Win32_OperatingSystem
    $ver = [Version]$os.Version
    if ($ver.Major -lt 10) {
        Write-Host "[ERROR] 仅支持 Windows 10 及以上。当前: $($os.Caption) ($($os.Version))" -ForegroundColor Red
        exit 1
    }
}

function Get-SystemDrive {
    return ($env:SystemDrive).TrimEnd('\')   # e.g. 'C:'
}

function Format-GB([long]$bytes) { '{0:N2} GB' -f ($bytes / 1GB) }

function Get-FreeSpaceGB {
    param([string]$Drive = (Get-SystemDrive))
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
    [math]::Round($d.FreeSpace / 1GB, 2)
}

function Get-UsedSpaceGB {
    param([string]$Drive = (Get-SystemDrive))
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$Drive'"
    [math]::Round(($d.Size - $d.FreeSpace) / 1GB, 2)
}

# Whitelist gate: refuse to recursively delete anything outside known temp paths.
$Script:SafePathPrefixes = @(
    'C:\Windows\Temp',
    "$env:TEMP",
    "$env:LOCALAPPDATA\Temp",
    'C:\Windows\SoftwareDistribution\Download',
    'C:\Windows\Prefetch',
    'C:\ProgramData\Microsoft\Windows\WER',
    'C:\Windows\Minidump',
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
    'C:\Windows\SoftwareDistribution\DeliveryOptimization\Cache',
    'C:\Recovery\Customizations'
) | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() }

function Test-SafePath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = try { (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { $Path }
    $lower = $resolved.TrimEnd('\').ToLowerInvariant()
    foreach ($prefix in $Script:SafePathPrefixes) {
        if ($lower -eq $prefix -or $lower.StartsWith("$prefix\")) { return $true }
    }
    return $false
}

function Remove-SafeContents {
    <#
    .SYNOPSIS
      Delete contents of a whitelisted folder, swallowing in-use file errors.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$WhatIf
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "    [skip] 不存在: $Path" -ForegroundColor DarkGray
        return 0
    }
    if (-not (Test-SafePath $Path)) {
        Write-Host "    [BLOCKED] 路径不在白名单，拒绝删除: $Path" -ForegroundColor Red
        return 0
    }
    $before = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
               Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $before) { $before = 0 }
    if ($WhatIf) {
        Write-Host ("    [dry-run] {0}  ({1})" -f $Path, (Format-GB $before)) -ForegroundColor Yellow
        return 0
    }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object Length -Sum -ErrorAction SilentlyContinue).Sum
    if (-not $after) { $after = 0 }
    $freed = $before - $after
    Write-Host ("    [ok] {0}  释放 {1}" -f $Path, (Format-GB $freed)) -ForegroundColor Green
    return $freed
}

function Confirm-Step {
    param([Parameter(Mandatory)][string]$Message)
    $ans = Read-Host "$Message  [y/N]"
    return ($ans -match '^(y|yes)$')
}

function Write-Section($title) {
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host (" $title ") -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}
