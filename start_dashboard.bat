@echo off
chcp 65001 >nul
title Exchange 邮箱仪表板 - 开发模式
echo ============================================
echo   Exchange 邮箱仪表板 - 开发模式
echo ============================================
echo.
echo  生产环境推荐使用 Nginx 反向代理
echo  部署文档见 nginx.conf + deploy.sh
echo.
echo  启动 Node.js 后端...
start /b "" "node" "C:\Users\oscarhuang\Documents\Project-06\server.js"
timeout /t 2 >nul
echo.
echo  本地访问: http://localhost:3099
echo.
echo  生产部署步骤:
echo    1. 将以下文件部署到 Linux 服务器:
echo       - server.js, index.html, nginx.conf, deploy.sh
echo    2. 运行: sudo bash deploy.sh 你的域名
echo    3. 在 Exchange 服务器上运行计划任务推送
echo.
pause
