# Exchange 邮箱清单导出 & 仪表板

Exchange 2016 邮箱用户清单导出工具，支持按数据库批量拉取 9000+ 邮箱的统计数据（大小、登录时间、AD 属性等），配套 Web 仪表板可搜索、排序、筛选，数据通过 HTTP 推送到前端服务器。

## 系统架构

+-----------------------------+        HTTPS 推送         +----------------------------------+
|  Exchange 服务器 (Windows)    | -----------------------> |  前端服务器 (Linux)                |
|                              |                          |                                  |
|  GetMailbox.ps1              |  每天定时任务 06:00       |  Nginx (端口 443, 域名)          |
|  导出 CSV + JSON             |  推送至 Nginx 域名        |   ↓ 反向代理                      |
|  日志: D:\Log\               |                          |  Node.js (127.0.0.1:3099)       |
|                              |                          |   ↓ 读取                         |
|                              |                          |  data/mailboxes.json             |
|                              |                          |                                  |
|                              |                          |  <- 用户浏览器访问仪表板            |
+-----------------------------+                          +----------------------------------+

## 文件说明

| 文件 | 部署位置 | 用途 |
|---|---|---|
| GetMailbox.ps1 | Exchange 服务器 | 导出邮箱数据 + 推送 JSON |
| server.js | Linux 服务器 | Node.js 后端，提供 API + 静态文件 |
| index.html | Linux 服务器 | 前端仪表板页面 |
| nginx.conf | Linux 服务器 | Nginx 反向代理配置模板 |
| deploy.sh | Linux 服务器 | 一键部署脚本 |
| setup_schedule.ps1 | Exchange 服务器 | 创建 Windows 计划任务 |

## CSV 导出字段

| 列名 | 说明 | 来源 |
|---|---|---|
| name | 姓名 | DisplayName |
| account | 账号 | SamAccountName |
| dept | 部门 | AD Department |
| ou | 组织 OU | 从 DistinguishedName 解析 |
| database | 所属邮箱数据库 | 从 Database DN 解析 |
| email | 邮箱地址 | PrimarySmtpAddress |
| sizeMB | 邮箱大小 (MB) | 从 TotalItemSize 解析 |
| createdOn | 创建时间 | AD WhenCreated |
| lastLogon | 上次登录时间 | MailboxStatistics LastLogonTime |
| status | 账号状态 | AD Enabled (启用/禁用) |

## 部署指南

### Exchange 服务器（Windows）

1. 将 `GetMailbox.ps1` 复制到 `D:\`
2. 手动运行测试：
   ```powershell
   D:\GetMailbox.ps1
   ```
3. 带推送运行：
   ```powershell
   D:\GetMailbox.ps1 -ServerUrl "https://mailbox-report.yourcompany.com"
   ```
4. 创建每日计划任务（06:00 自动运行）：
   ```powershell
   D:\setup_schedule.ps1 -ServerUrl "https://mailbox-report.yourcompany.com"
   ```

### 前端服务器（Linux）

1. 将 `server.js`、`index.html`、`nginx.conf`、`deploy.sh` 放到同一目录
2. 运行部署脚本：
   ```bash
   sudo bash deploy.sh mailbox-report.yourcompany.com
   ```
3. 配置 SSL 证书（推荐 Certbot）：
   ```bash
   sudo certbot --nginx -d mailbox-report.yourcompany.com
   ```

### 开发/测试模式（无 Nginx）

```bash
# 启动 Node.js 后端（监听所有网络接口）
node server.js 0.0.0.0

# Exchange 服务器推送测试
D:\GetMailbox.ps1 -ServerUrl "http://192.168.x.x:3099"
```

### 生产模式（Nginx 反向代理）

```bash
# 启动 Node.js 后端（仅监听本地，安全隔离）
node server.js

# Exchange 服务器推送
D:\GetMailbox.ps1 -ServerUrl "https://mailbox-report.yourcompany.com"
```

## 仪表板功能

- 统计卡片：总邮箱数、启用数、禁用数、总容量
- 实时搜索：姓名、账号、邮箱、部门、OU 模糊搜索
- 列排序：点击表头排序，支持中文
- 列显隐：右上角"显示列"切换列显示
- 导出 CSV：当前筛选结果一键下载

## 日志记录

每次运行自动生成日志文件：`D:\Log\MailboxReport_YYYYMMDD_HHmmss.log`

```
[2026-06-24 10:30:00] [INFO] ===== Exchange 邮箱清单导出开始 =====
[2026-06-24 10:30:22] [INFO] 第1步 Get-Mailbox — 共 9317 个邮箱 (22秒)
[2026-06-24 10:33:15] [INFO] 第2步 Get-MailboxStatistics — 共 9317 条记录 (194秒)
[2026-06-24 10:37:45] [INFO] HTTP 推送 — 成功 (23秒)
[2026-06-24 10:37:45] [INFO] 总耗时: 7分44秒
```

自动保留 30 天，过期日志自动清理。

## 注意事项

- 在 Exchange Management Shell 中以管理员身份运行脚本
- 9000+ 邮箱建议非高峰时段运行
- 如需 Basic Auth 认证仪表板，在 nginx.conf 中添加 auth_basic 配置
- PowerShell 推送时自动将请求体编码为 UTF-8，避免中文乱码
