<#
.SYNOPSIS
  Stage 8: backup and delete OEM provisioning packages under C:\Recovery.
.PARAMETER BackupDir
  Required. Must be on a non-system drive. Files are copied here before deletion
  and verified by size and SHA-256 before the original is removed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BackupDir
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

Write-Section "阶段 8：删除 OEM 出厂预装包 (.ppkg)"

$sys = (Get-SystemDrive).TrimEnd(':')
$backupRoot = (Resolve-Path -LiteralPath $BackupDir -ErrorAction SilentlyContinue)
if (-not $backupRoot) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $backupRoot = (Resolve-Path -LiteralPath $BackupDir).Path
} else {
    $backupRoot = $backupRoot.Path
}

if ($backupRoot -like "$sys`:*") {
    Write-Host "[ERROR] -BackupDir 必须在非系统盘 (当前: $backupRoot)。" -ForegroundColor Red
    exit 1
}

$candidates = @()
foreach ($root in @('C:\Recovery\Customizations','C:\Recovery\OEM')) {
    if (Test-Path -LiteralPath $root) {
        $candidates += Get-ChildItem -LiteralPath $root -Filter '*.ppkg' -File -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $candidates) {
    Write-Host "未发现 .ppkg 文件。" -ForegroundColor Green
    return
}

$candidates | Select-Object FullName,
    @{N='SizeGB';E={[math]::Round($_.Length/1GB,2)}}, LastWriteTime |
    Format-Table -AutoSize

if (-not (Confirm-Step "确认备份到 $backupRoot 然后删除？")) { return }

$runBackup = Join-Path $backupRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runBackup -ErrorAction Stop | Out-Null

foreach ($f in $candidates) {
    if (-not (Test-SafePath $f.FullName)) { throw "Unsafe source: $($f.FullName)" }
    # Keep each source's relative directory, including Customizations/OEM.
    $relative = $f.FullName.Substring('C:\Recovery\'.Length)
    $dest = Join-Path $runBackup $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Write-Host "[1/3] 复制: $($f.FullName) → $dest"
    [IO.File]::Copy($f.FullName, $dest, $false)

    Write-Host "[2/3] 校验大小和 SHA-256"
    $srcLen = (Get-Item -LiteralPath $f.FullName).Length
    $dstLen = (Get-Item -LiteralPath $dest).Length
    $srcHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
    if ($srcLen -ne $dstLen -or $srcHash -ne $dstHash) {
        Write-Host "[ABORT] 大小或 SHA-256 不匹配 ($srcLen vs $dstLen)，保留原文件。" -ForegroundColor Red
        continue
    }

    if (-not (Test-SafePath $f.FullName)) {
        Write-Host "[BLOCKED] 路径不在白名单: $($f.FullName)" -ForegroundColor Red
        continue
    }

    Write-Host "[3/3] 删除原文件"
    Remove-Item -LiteralPath $f.FullName -Force
    Write-Host "  [ok] 已删除 (释放 $(Format-GB $srcLen))" -ForegroundColor Green
}

Write-Host ""
Write-Host "完成。备份位于: $backupRoot" -ForegroundColor Cyan
Write-Host "Restore each file from its matching Customizations/OEM subdirectory to C:\Recovery; backup run: $runBackup" -ForegroundColor DarkGray
