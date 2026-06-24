# Exchange 邮箱清单 - 创建每日计划任务（含推送）
# 在 Exchange Management Shell 中以管理员身份运行
# 用法:
#   .\setup_schedule.ps1                                          # 仅本地导出
#   .\setup_schedule.ps1 -ServerUrl "https://mailbox-report.yourcompany.com"  # 导出并推送

param(
    [string]$ServerUrl = ""
)

$scriptPath = "D:\GetMailbox.ps1"
$taskName   = "ExchangeMailboxReport"

if ($ServerUrl -ne "") {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ServerUrl `"$ServerUrl`""
} else {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Daily -At 06:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force

Write-Host "计划任务已创建：" -ForegroundColor Green
Write-Host "  名称: $taskName" -ForegroundColor Yellow
Write-Host "  时间: 每天 06:00" -ForegroundColor Yellow
Write-Host "  脚本: $scriptPath" -ForegroundColor Yellow
if ($ServerUrl -ne "") {
    Write-Host "  推送: $ServerUrl/api/upload" -ForegroundColor Yellow
}
Write-Host "`n查看任务: Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
Write-Host "手动运行: Start-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
