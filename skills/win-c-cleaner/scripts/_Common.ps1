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

function Get-SystemFileInfo {
    <#
    .SYNOPSIS
      Return a FileInfo for a path, working around the FileSystem provider's
      failure on kernel-locked files.
    .DESCRIPTION
      Test-Path / Get-Item report hiberfil.sys, pagefile.sys and swapfile.sys as
      non-existent because the provider cannot open them (exclusive kernel lock).
      Enumerating the parent directory with -Force returns them correctly.
      Returns $null when the file genuinely does not exist.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $dir  = Split-Path -Parent $Path
    $name = Split-Path -Leaf   $Path
    if (-not $dir) { return $null }
    Get-ChildItem -LiteralPath $dir -Force -File -Filter $name -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-FolderSize {
    <#
    .SYNOPSIS
      Total size in bytes of a folder tree. Returns 0 for empty/unreadable trees.
    .DESCRIPTION
      Get-ChildItem without -File yields DirectoryInfo objects, which have no
      Length property. When a tree contains no files at all, Measure-Object
      throws GenericMeasurePropertyNotFound, and because _Common.ps1 sets
      $ErrorActionPreference = 'Stop' that aborts the whole script.
    #>
    param([Parameter(Mandatory)][string]$Path)
    # Keep the Measure-Object result in a variable: with no input it returns
    # $null, and Set-StrictMode -Version Latest turns a direct .Sum access on
    # $null into a terminating PropertyNotFoundStrict error.
    $measured = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum -ErrorAction SilentlyContinue
    if ($null -ne $measured -and $null -ne $measured.Sum) { [long]$measured.Sum } else { [long]0 }
}

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
    'C:\Recovery\Customizations',
    # Stage 8 enumerates C:\Recovery\OEM as a .ppkg source, so it must be
    # whitelisted too; otherwise those files are backed up and then refused.
    'C:\Recovery\OEM'
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

function Get-PropertyOrNull {
    <#
    .SYNOPSIS
      Read a property that may not exist, without tripping Set-StrictMode.
    .DESCRIPTION
      Under Set-StrictMode -Version Latest, touching a property an object does
      not have is a terminating error. Registry uninstall keys are irregular:
      plenty of them have no DisplayName or UninstallString at all.
    #>
    param($InputObject, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($prop) { $prop.Value } else { $null }
}

function Invoke-NativeOem {
    <#
    .SYNOPSIS
      Run a native command with [Console]::OutputEncoding pinned to the console
      OEM code page, then restore it.
    .DESCRIPTION
      Windows PowerShell decodes a native command's stdout using
      [Console]::OutputEncoding. DISM emits text in the console OEM code page
      (936 on zh-CN, 932 on ja-JP, ...). Any host that leaves OutputEncoding at
      UTF-8 turns that into mojibake, so downstream -match on localized strings
      silently matches nothing and the WinSxS report comes out blank.
    #>
    param([Parameter(Mandatory)][scriptblock]$Command)
    $prev = [Console]::OutputEncoding
    try {
        $nls = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name OEMCP -ErrorAction SilentlyContinue
        if ($nls -and $nls.OEMCP) {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding([int]$nls.OEMCP)
        }
        & $Command
    } finally {
        [Console]::OutputEncoding = $prev
    }
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
