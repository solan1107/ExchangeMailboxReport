#!/bin/bash
# ============================================================
# Exchange 邮箱仪表板 - Linux 部署脚本
# 在目标 Linux 服务器上以 root 或 sudo 身份运行
# 使用方法: sudo bash deploy.sh
# ============================================================

set -euo pipefail

APP_DIR="/opt/mailbox-report"
DOMAIN="${1:-mailbox-report.yourcompany.com}"

echo "============================================"
echo " Exchange 邮箱仪表板 - 部署脚本"
echo "============================================"
echo "安装目录: $APP_DIR"
echo "域名: $DOMAIN"
echo ""

# 1. 创建目录
mkdir -p "$APP_DIR/data"

# 2. 复制文件
echo "[1/4] 复制应用文件..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/server.js" "$APP_DIR/"
cp "$SCRIPT_DIR/index.html" "$APP_DIR/"
chmod 644 "$APP_DIR/server.js" "$APP_DIR/index.html"

# 3. 安装 Node.js 依赖（如果需要）
# 本项目使用纯 Node.js 内置模块，无需 npm install

# 4. 创建 systemd 服务（开机自启）
echo "[2/4] 创建 systemd 服务..."
cat > /etc/systemd/system/mailbox-report.service << 'SERVICE'
[Unit]
Description=Exchange Mailbox Report Dashboard
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/mailbox-report
ExecStart=/usr/bin/node /opt/mailbox-report/server.js
Restart=always
RestartSec=10
StandardOutput=append:/var/log/mailbox-report.log
StandardError=append:/var/log/mailbox-report.log

[Install]
WantedBy=multi-user.target
SERVICE

# 5. 配置 Nginx
echo "[3/4] 配置 Nginx..."
sed "s/mailbox-report.yourcompany.com/$DOMAIN/g" "$SCRIPT_DIR/nginx.conf" > /etc/nginx/sites-available/mailbox-report
ln -sf /etc/nginx/sites-available/mailbox-report /etc/nginx/sites-enabled/

# 6. 创建日志目录
mkdir -p /var/log/nginx
touch /var/log/mailbox-report.log
chown www-data:www-data /var/log/mailbox-report.log

# 7. 启动服务
echo "[4/4] 启动服务..."
systemctl daemon-reload
systemctl enable mailbox-report
systemctl restart mailbox-report
nginx -t && systemctl reload nginx

echo ""
echo "============================================"
echo " 部署完成！"
echo "============================================"
echo ""
echo "服务状态:"
systemctl status mailbox-report --no-pager | head -5
echo ""
echo "下一步操作:"
echo "  1. 配置 DNS: 将 $DOMAIN 指向本机 IP"
echo "  2. 配置 SSL:"
echo "     推荐使用 Certbot: sudo certbot --nginx -d $DOMAIN"
echo "     或手动放置证书到 /etc/nginx/ssl/mailbox-report/"
echo "  3. 在 Exchange 服务器上运行:"
echo "     D:\GetMailbox.ps1 -ServerUrl \"https://$DOMAIN\""
echo "  4. 设置定时推送: 在 Exchange EMS 中运行"
echo "     D:\setup_schedule.ps1  并添加 -ServerUrl 参数"
echo ""
