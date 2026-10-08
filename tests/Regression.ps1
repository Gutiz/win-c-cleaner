# Safe standalone regression checks. Requires Windows PowerShell 5.1 or newer.
# No admin rights, real recovery paths, native cleanup commands or external modules.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scripts = Join-Path $PSScriptRoot '..\skills\win-c-cleaner\scripts'
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
Get-ChildItem $scripts -Filter *.ps1 | ForEach-Object {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors)
    Assert ($errors.Count -eq 0) "Parse failed: $($_.Name)"
    $bytes = [IO.File]::ReadAllBytes($_.FullName)
    Assert ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) "Missing UTF-8 BOM: $($_.Name)"
}
. (Join-Path $scripts '_Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('win-c-cleaner-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$Script:SafePathPrefixes += $fixture.ToLowerInvariant()
$empty = Join-Path $fixture 'empty'
New-Item -ItemType Directory -Path $empty | Out-Null
Assert ((Remove-SafeContents $empty -WhatIf) -eq 0) 'Empty preview must return zero'
Assert ((Remove-SafeContents $empty) -eq 0) 'Empty execution must return zero'
$file = Join-Path $empty 'sample.bin'
[IO.File]::WriteAllBytes($file, [byte[]](1,2,3))
Assert ((Remove-SafeContents $empty -WhatIf) -eq 0) 'Preview must return zero'
Assert (Test-Path -LiteralPath $file) 'Preview removed a file'
Assert ((Remove-SafeContents $empty) -eq 3) 'Actual fixture cleanup must report three bytes'
Assert (-not (Test-Path -LiteralPath $file)) 'Fixture cleanup left file'
Assert ((Get-FolderSize $empty) -eq 0) 'Empty tree size'
Assert ((Get-FolderSize (Join-Path $fixture 'missing')) -eq 0) 'Missing tree size'
Assert ($null -eq (Get-PropertyOrNull ([pscustomobject]@{}) 'Absent')) 'Optional property'

# Run the actual Stage 8 body, substituting ONLY environment setup and recovery root.
# All copy/hash/delete operations below are real operations confined to this fixture.
$recovery = Join-Path $fixture 'Recovery'
$backup = Join-Path $fixture 'backup'
$sources = @('Customizations\same.ppkg','OEM\same.ppkg','OEM\nested\same.ppkg')
$stage = [IO.File]::ReadAllText((Join-Path $scripts 'Invoke-Stage8-RemovePpkg.ps1'))
$stage = $stage.Replace('. "$PSScriptRoot\_Common.ps1"', '')
$stage = $stage.Replace('C:\Recovery', $recovery)
function Assert-Admin {}
function Assert-Windows10Plus {}
function Get-SystemDrive { 'Z:' } # The fixture is not a system volume.
function Confirm-Step { $true }
function Seed-Packages {
    for ($i = 0; $i -lt $sources.Count; $i++) {
        $path = Join-Path $recovery $sources[$i]
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [IO.File]::WriteAllBytes($path, [byte[]]($i,10,20))
    }
}
Seed-Packages
for ($run = 1; $run -le 2; $run++) {
    & ([scriptblock]::Create($stage)) -BackupDir $backup | Out-Null
    $runs = @(Get-ChildItem -LiteralPath $backup -Directory)
    Assert ($runs.Count -eq $run) 'Each execution needs a separate backup directory'
    foreach ($savedRun in $runs) {
        for ($i = 0; $i -lt $sources.Count; $i++) {
            $saved = Join-Path $savedRun.FullName $sources[$i]
            Assert (([IO.File]::ReadAllBytes($saved) -join ',') -eq "$i,10,20") 'Backup contents overwritten'
        }
    }
    foreach ($source in $sources) { Assert (-not (Test-Path (Join-Path $recovery $source))) 'Verified source not removed' }
    Seed-Packages
}
function Confirm-Step { $false }
& ([scriptblock]::Create($stage)) -BackupDir $backup | Out-Null
Assert (@(Get-ChildItem $backup -Directory).Count -eq 2) 'Cancellation created a backup run'
foreach ($source in $sources) { Assert (Test-Path (Join-Path $recovery $source)) 'Cancellation removed source' }

# Corrupt the reported destination hash. The source must survive failed verification.
function Confirm-Step { $true }
function Get-FileHash {
    param($LiteralPath, $Algorithm)
    if ($LiteralPath.StartsWith($backup, [StringComparison]::OrdinalIgnoreCase)) {
        [pscustomobject]@{Hash='deliberately-invalid'}
    } else { Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm }
}
& ([scriptblock]::Create($stage)) -BackupDir $backup | Out-Null
foreach ($source in $sources) { Assert (Test-Path (Join-Path $recovery $source)) 'Hash mismatch removed source' }
Remove-Item Function:\Get-FileHash
# Simulate a destination appearing between run-directory creation and copying.
# File.Copy(overwrite=false) must stop, keeping both source and existing backup.
$script:collision = $null
function New-Item {
    [CmdletBinding()]
    param($ItemType, $Path, [switch]$Force)
    $result = Microsoft.PowerShell.Management\New-Item -ItemType $ItemType -Path $Path -Force:$Force
    if ((Split-Path -Parent $Path) -eq $backup) {
        $script:collision = Join-Path $Path 'Customizations\same.ppkg'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $script:collision)) | Out-Null
        [IO.File]::WriteAllBytes($script:collision, [byte[]](99,98,97))
    }
    $result
}
$failed = $false
try { & ([scriptblock]::Create($stage)) -BackupDir $backup | Out-Null } catch { $failed = $true }
Assert $failed 'Existing destination must stop copying'
Assert (([IO.File]::ReadAllBytes($script:collision) -join ',') -eq '99,98,97') 'Existing backup overwritten'
foreach ($source in $sources) { Assert (Test-Path (Join-Path $recovery $source)) 'Copy failure removed source' }
Remove-Item Function:\New-Item
"PASS: 13 scripts parse with BOM; empty/preview/fixture cleanup; same-name backups across roots and nested directories; repeated runs; cancellation; hash mismatch. PowerShell $($PSVersionTable.PSVersion). Fixtures retained at $fixture"
