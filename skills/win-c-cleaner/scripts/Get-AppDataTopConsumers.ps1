<#
.SYNOPSIS
  Audit AppData\Local and AppData\Roaming top consumers.
.PARAMETER TopN
  Number of folders to display per location (default 15).
.PARAMETER MinGB
  Minimum size in GB to include (default 0.1).
#>
[CmdletBinding()]
param(
    [int]$TopN = 15,
    [double]$MinGB = 0.1
)

. "$PSScriptRoot\_Common.ps1"

function Get-TopFolders([string]$Root, [int]$N, [double]$Min) {
    Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $sum = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object Length -Sum).Sum
        [PSCustomObject]@{
            Name   = $_.Name
            SizeGB = [math]::Round(($sum | ForEach-Object { if ($_) { $_ } else { 0 } }) / 1GB, 2)
        }
    } | Where-Object { $_.SizeGB -ge $Min } |
        Sort-Object SizeGB -Descending |
        Select-Object -First $N
}

Write-Section "AppData\Local Top $TopN ($env:LOCALAPPDATA)"
Get-TopFolders $env:LOCALAPPDATA $TopN $MinGB | Format-Table -AutoSize

Write-Section "AppData\Roaming Top $TopN ($env:APPDATA)"
Get-TopFolders $env:APPDATA $TopN $MinGB | Format-Table -AutoSize
