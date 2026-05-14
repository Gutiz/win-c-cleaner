<#
.SYNOPSIS
  Stage 7: list common OEM bloatware (Dell/Lenovo/HP/ASUS/Acer + trial software)
  installed on the system. Uninstall on user confirmation, one at a time.

  Does NOT auto-remove anything. Caller picks per-item.
#>
[CmdletBinding()]
param(
    [switch]$IncludeRiskyFunctionKeys   # also show items that can affect Fn keys / power
)

. "$PSScriptRoot\_Common.ps1"
Assert-Admin
Assert-Windows10Plus

Write-Section "阶段 7：OEM 预装软件审查"

$safeMatches = @(
    # vendor name patterns => display label
    @{ Pattern = 'Dell SupportAssist';            Vendor = 'Dell';   Note = '遥测，存在历史漏洞' },
    @{ Pattern = 'Dell SupportAssist OS Recovery';Vendor = 'Dell';   Note = '恢复插件' },
    @{ Pattern = 'Dell Update';                   Vendor = 'Dell';   Note = '可用 Windows Update 替代' },
    @{ Pattern = 'Dell Optimizer';                Vendor = 'Dell';   Note = '后台优化器' },
    @{ Pattern = 'Dell Digital Delivery';         Vendor = 'Dell';   Note = '预装软件商城' },
    @{ Pattern = 'Lenovo Vantage';                Vendor = 'Lenovo'; Note = '部分功能 Windows 自带' },
    @{ Pattern = 'Lenovo Now';                    Vendor = 'Lenovo'; Note = '广告应用' },
    @{ Pattern = 'Lenovo Welcome';                Vendor = 'Lenovo'; Note = '欢迎应用' },
    @{ Pattern = 'Lenovo Smart Privacy';          Vendor = 'Lenovo'; Note = '可选' },
    @{ Pattern = 'HP Support Assistant';          Vendor = 'HP';     Note = '可用 Windows Update 替代' },
    @{ Pattern = 'HP JumpStart';                  Vendor = 'HP';     Note = '广告应用' },
    @{ Pattern = 'HP Wolf Security';              Vendor = 'HP';     Note = '可选，部分用户不需要' },
    @{ Pattern = 'MyASUS';                        Vendor = 'ASUS';   Note = '可选' },
    @{ Pattern = 'ASUS GiftBox';                  Vendor = 'ASUS';   Note = '广告应用' },
    @{ Pattern = 'Acer Care Center';              Vendor = 'Acer';   Note = '可选' },
    @{ Pattern = 'Acer Collection';               Vendor = 'Acer';   Note = '广告应用' },
    @{ Pattern = 'McAfee LiveSafe';               Vendor = 'McAfee'; Note = '试用版' },
    @{ Pattern = 'McAfee WebAdvisor';             Vendor = 'McAfee'; Note = '试用版' },
    @{ Pattern = 'Norton';                        Vendor = 'Norton'; Note = '试用版' },
    @{ Pattern = 'ExpressVPN';                    Vendor = '试用';   Note = '通常是试用捆绑' }
)
$riskyMatches = @(
    @{ Pattern = 'Dell Core Services';            Vendor = 'Dell';   Note = '⚠️ 影响功能键/电源' },
    @{ Pattern = 'Lenovo System Interface';       Vendor = 'Lenovo'; Note = '⚠️ 影响 Fn 键' },
    @{ Pattern = 'Lenovo Power Management';       Vendor = 'Lenovo'; Note = '⚠️ 影响电源' },
    @{ Pattern = 'HP System Default Settings';    Vendor = 'HP';     Note = '⚠️ 系统默认设置' }
)
$matchList = if ($IncludeRiskyFunctionKeys) { $safeMatches + $riskyMatches } else { $safeMatches }

Write-Host "枚举已安装程序 (从注册表读取，几秒)..."
$paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = foreach ($p in $paths) {
    Get-ItemProperty -Path $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher,
            @{N='UninstallString';E={$_.UninstallString}},
            @{N='QuietUninstallString';E={$_.QuietUninstallString}}
}

$found = foreach ($m in $matchList) {
    foreach ($app in $installed) {
        if ($app.DisplayName -like "*$($m.Pattern)*") {
            [PSCustomObject]@{
                DisplayName     = $app.DisplayName
                Version         = $app.DisplayVersion
                Vendor          = $m.Vendor
                Note            = $m.Note
                Uninstall       = if ($app.QuietUninstallString) { $app.QuietUninstallString } else { $app.UninstallString }
            }
        }
    }
} | Sort-Object DisplayName -Unique

if (-not $found) {
    Write-Host "未检测到匹配的 OEM 预装软件。" -ForegroundColor Green
    return
}

$i = 0
$found = $found | ForEach-Object {
    $i++
    $_ | Add-Member -NotePropertyName 'Index' -NotePropertyValue $i -PassThru
}

$found | Select-Object Index, DisplayName, Version, Vendor, Note | Format-Table -AutoSize

Write-Host ""
Write-Host "选择要卸载的编号（多个用逗号，回车跳过）：" -ForegroundColor Yellow
$picks = Read-Host ">"
if (-not $picks) { Write-Host '已跳过。' ; return }

$indices = $picks -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }

foreach ($idx in $indices) {
    $row = $found | Where-Object Index -eq $idx | Select-Object -First 1
    if (-not $row) { continue }
    if (-not $row.Uninstall) {
        Write-Host "[skip] $($row.DisplayName) 无卸载命令" -ForegroundColor Yellow
        continue
    }
    if (-not (Confirm-Step "卸载: $($row.DisplayName) ？")) { continue }

    # Try winget first (cleaner)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    $done = $false
    if ($winget) {
        try {
            & winget uninstall --name "$($row.DisplayName)" --silent --accept-source-agreements 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [ok via winget] $($row.DisplayName)" -ForegroundColor Green
                $done = $true
            }
        } catch { }
    }

    if (-not $done) {
        # Fallback: run UninstallString. Try to add /quiet or /S to MSI/InstallShield.
        $cmd = $row.Uninstall
        if ($cmd -match '(?i)msiexec') {
            $cmd = $cmd -replace '(?i)/i','/x'
            if ($cmd -notmatch '/(qn|quiet)') { $cmd = "$cmd /qn /norestart" }
        }
        Write-Host "  执行: $cmd"
        try {
            Start-Process -FilePath cmd.exe -ArgumentList "/c $cmd" -Wait -NoNewWindow
            Write-Host "  [ok] $($row.DisplayName)" -ForegroundColor Green
        } catch {
            Write-Host "  [fail] $($row.DisplayName): $_" -ForegroundColor Red
        }
    }
}
