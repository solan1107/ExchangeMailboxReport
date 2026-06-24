# ============================================================
# Exchange 2016 邮箱清单导出（9000+ 优化版）
# 配合前端仪表板使用，支持 HTTP 推送到前端服务
# 在 Exchange Management Shell 中以管理员身份运行
# 用法:
#   本地导出:                 D:\GetMailbox.ps1
#   导出并推送到前端:         D:\GetMailbox.ps1 -ServerUrl "https://mailbox-report.yourcompany.com"
# ============================================================

param(
    [string]$ServerUrl = ""
)

Import-Module ActiveDirectory -ErrorAction Stop

# ============================================================
# 日志配置
# ============================================================
$logDir = "D:\Log"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = "D:\Log\MailboxReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message"
}

# 清理 30 天前的旧日志
try {
    $cutoff = (Get-Date).AddDays(-30)
    Get-ChildItem $logDir -Filter "MailboxReport_*.log" | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
} catch {}

$scriptSw = [System.Diagnostics.Stopwatch]::StartNew()

Write-Log "===== Exchange 邮箱清单导出开始 ====="
if ($ServerUrl -ne "") { Write-Log "推送目标: $ServerUrl" }
Write-Log ""

# ============================================================
# 导出路径
# ============================================================
$exportPath = "D:\MailboxReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$exportDir  = Split-Path $exportPath -Parent
if (!(Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }

$jsonPath   = Join-Path $exportDir "mailboxes.json"
$summaryPath = Join-Path $exportDir "summary.json"

# ============================================================
# 第1步：获取所有用户邮箱
# ============================================================
$stepSw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "第1步：获取所有用户邮箱..." -ForegroundColor Cyan
$mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
$stepSw.Stop()
Write-Host "共找到 $($mailboxes.Count) 个邮箱" -ForegroundColor Green
Write-Log "第1步 Get-Mailbox — 共 $($mailboxes.Count) 个邮箱 ($([math]::Round($stepSw.Elapsed.TotalSeconds))秒)"
Write-Log ""

# ============================================================
# 第2步：获取邮箱大小统计（按数据库分批查询）
# ============================================================
$stepSw.Restart()
Write-Host "第2步：获取邮箱大小统计（按数据库分批查询）..." -ForegroundColor Cyan
$statsHash = @{}
$databases = Get-MailboxDatabase -ErrorAction SilentlyContinue
$dbCount = 0
$dbIdx = 0
if ($databases) { $dbCount = @($databases).Count }

if ($dbCount -gt 0) {
    foreach ($db in $databases) {
        $dbIdx++
        Write-Progress -Activity "获取邮箱统计" -Status "数据库 ($dbIdx/$dbCount): $($db.Name)" -PercentComplete (($dbIdx / $dbCount) * 100)
        try {
            $dbStats = Get-MailboxStatistics -Database $db.Identity -ErrorAction SilentlyContinue
            if ($dbStats) {
                @($dbStats) | ForEach-Object {
                    $statsHash[$_.MailboxGuid.ToString()] = $_
                }
            }
        } catch {
            # 跳过无法访问的数据库
        }
    }
    Write-Progress -Activity "获取邮箱统计" -Completed
} else {
    Write-Host "  无法枚举数据库，改用分批查询..." -ForegroundColor Yellow
    Write-Log "  备用方案：分批查询" "WARN"
    $batchSize = 300
    $total = $mailboxes.Count
    for ($i = 0; $i -lt $total; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize - 1, $total - 1)
        Write-Progress -Activity "获取邮箱统计（分批）" -Status "$i ~ $end / $total" -PercentComplete (($i / $total) * 100)
        try {
            $mailboxes[$i..$end] | Get-MailboxStatistics -ErrorAction SilentlyContinue | ForEach-Object {
                $statsHash[$_.MailboxGuid.ToString()] = $_
            }
        } catch {}
    }
    Write-Progress -Activity "获取邮箱统计（分批）" -Completed
}
$stepSw.Stop()
Write-Host "共获取 $($statsHash.Count) 条统计记录" -ForegroundColor Green
Write-Log "第2步 Get-MailboxStatistics — 共 $($statsHash.Count) 条记录 ($([math]::Round($stepSw.Elapsed.TotalSeconds))秒)"
Write-Log ""

# ============================================================
# 第3步：批量获取 AD 用户信息
# ============================================================
$stepSw.Restart()
Write-Host "第3步：批量获取 AD 用户信息..." -ForegroundColor Cyan
$adHash = @{}
Get-ADUser -Filter * -Properties Department, Enabled, WhenCreated | ForEach-Object {
    $adHash[$_.SamAccountName] = $_
}
$stepSw.Stop()
Write-Log "第3步 Get-ADUser — 共 $($adHash.Count) 个用户 ($([math]::Round($stepSw.Elapsed.TotalSeconds))秒)"
Write-Log ""

# ============================================================
# 第4步：组装并导出
# ============================================================
$stepSw.Restart()
Write-Host "第4步：组装并导出..." -ForegroundColor Cyan
$results = foreach ($mbx in $mailboxes) {
    $guid = $mbx.ExchangeGuid.ToString()
    $stats = $statsHash[$guid]

    $adUser = $adHash[$mbx.SamAccountName]
    $status = if ($adUser -and $adUser.Enabled) { "启用" } else { "禁用" }
    $dept   = if ($adUser) { $adUser.Department } else { "" }
    $createdOn = if ($adUser -and $adUser.WhenCreated) { $adUser.WhenCreated.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }

    # 邮箱大小
    $sizeMB = $null
    if ($stats -and $stats.TotalItemSize) {
        $sizeStr = $stats.TotalItemSize.ToString()
        if ($sizeStr -match '\(([\d,]+)\s*bytes\)') {
            $sizeBytes = [long]($matches[1] -replace ',', '')
            $sizeMB = [math]::Round($sizeBytes / 1MB, 2)
        }
    }

    # 上次登录时间
    $lastLogonOn = if ($stats -and $stats.LastLogonTime) { $stats.LastLogonTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }

    # 完整 OU 路径
    $dn = $mbx.DistinguishedName
    $ous = @()
    ($dn -split ',') | ForEach-Object {
        if ($_ -match '^OU=(.+)$') { $ous = ,$matches[1] + $ous }
    }
    $fullOu = if ($ous.Count -gt 0) { $ous -join '/' } else { "" }

    # 所属邮箱数据库
    $dbName = ""
    if ($mbx.Database) {
        $dbStr = $mbx.Database.ToString()
        if ($dbStr -match 'CN=([^,]+)') { $dbName = $matches[1] }
    }

    [PSCustomObject]@{
        name      = $mbx.DisplayName
        account   = $mbx.SamAccountName
        dept      = $dept
        ou        = $fullOu
        database  = $dbName
        email     = if ($mbx.PrimarySmtpAddress) { $mbx.PrimarySmtpAddress.ToString() } else { "" }
        sizeMB    = $sizeMB
        createdOn = $createdOn
        lastLogon = $lastLogonOn
        status    = $status
    }
}
$stepSw.Stop()
$exportTime = $stepSw.Elapsed.TotalSeconds

# 导出 CSV
$results | Export-Csv -Path $exportPath -NoTypeInformation -Encoding Default
Write-Host "CSV文件: $exportPath" -ForegroundColor Yellow

# 导出 JSON
$results | ConvertTo-Json -Depth 2 | Out-File -FilePath $jsonPath -Encoding UTF8
Write-Host "JSON文件: $jsonPath" -ForegroundColor Yellow

Write-Log "第4步 组装+导出 — 共 $($results.Count) 行 ($([math]::Round($exportTime))秒)"
Write-Log "  CSV: $exportPath"
Write-Log "  JSON: $jsonPath"
Write-Log ""

# ============================================================
# 汇总统计
# ============================================================
$activeCount   = ($results | Where-Object { $_.status -eq "启用" }).Count
$inactiveCount = ($results | Where-Object { $_.status -eq "禁用" }).Count
$totalSizeGB   = [math]::Round(($results | Measure-Object -Property sizeMB -Sum).Sum / 1024, 2)

$summary = [PSCustomObject]@{
    updateTime  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    total       = $results.Count
    active      = $activeCount
    inactive    = $inactiveCount
    totalSizeGB = $totalSizeGB
}
$summary | ConvertTo-Json | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host "`n导出完成！共 $($results.Count) 个邮箱" -ForegroundColor Green
Write-Log "汇总 — 总计: $($results.Count), 启用: $activeCount, 禁用: $inactiveCount, 总容量: ${totalSizeGB}GB"

# ============================================================
# 推送到前端服务
# ============================================================
if ($ServerUrl -ne "") {
    Write-Host "`n正在推送到前端服务: $ServerUrl ..." -ForegroundColor Cyan
    $stepSw.Restart()
    try {
        $payload = @{
            mailboxes = $results
            summary   = $summary
        } | ConvertTo-Json -Depth 3

        $utf8Body = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $response = Invoke-RestMethod -Uri "$ServerUrl/api/upload" -Method Post -Body $utf8Body -ContentType "application/json; charset=utf-8" -ErrorAction Stop
        $stepSw.Stop()
        Write-Host "推送成功！服务器响应: $($response.message)" -ForegroundColor Green
        Write-Log "HTTP 推送 — 成功 ($([math]::Round($stepSw.Elapsed.TotalSeconds))秒)"
    }
    catch {
        $stepSw.Stop()
        Write-Host "推送失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "请检查网络连通性和服务器地址是否正确。" -ForegroundColor Yellow
        Write-Log "HTTP 推送 — 失败: $($_.Exception.Message) ($([math]::Round($stepSw.Elapsed.TotalSeconds))秒)" "ERROR"
    }
}
else {
    Write-Log "HTTP 推送 — 跳过（未指定 -ServerUrl）" "WARN"
    Write-Host "`n提示: 添加 -ServerUrl 参数可将数据推送到前端仪表板" -ForegroundColor Cyan
    Write-Host "  例如: D:\GetMailbox.ps1 -ServerUrl ""https://mailbox-report.yourcompany.com""" -ForegroundColor Cyan
}

# ============================================================
# 结束
# ============================================================
$scriptSw.Stop()
$totalSeconds = $scriptSw.Elapsed.TotalSeconds
if ($totalSeconds -ge 60) {
    $totalStr = "$([math]::Round($totalSeconds / 60, 1))分$([math]::Round($totalSeconds % 60))秒"
} else {
    $totalStr = "$([math]::Round($totalSeconds))秒"
}
Write-Log "总耗时: $totalStr"
Write-Log "日志文件: $logFile"
Write-Log "===== 导出完成 ====="
