#!/bin/bash
# 3x-ui 自定义一键安装脚本 | Fork版本
# 环境变量可传参：PANEL_USER PANEL_PASS PANEL_PORT PANEL_WEB_PATH VMESS_PORT
# PANEL_USER=myadmin PANEL_PASS=MyPass@888 PANEL_PORT=55221 PANEL_WEB_PATH=/admin VMESS_PORT=25000 bash <(curl -Ls https://raw.githubusercontent.com/JuiceArray/3x-ui/main/my‑3xui‑install.sh)

PANEL_USER="${PANEL_USER:-admin}"
PANEL_PASS="${PANEL_PASS:-Admin@123456}"
PANEL_PORT="${PANEL_PORT:-54321}"
PANEL_WEB_PATH="${PANEL_WEB_PATH:-/panel}"
VMESS_PORT="${VMESS_PORT:-20000}"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}错误：必须root运行！${plain}" && exit 1

# 系统检测
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
fi

get_arch(){
    arch=$(uname -m)
    if [[ $arch == x86_64* ]]; then
        arch="amd64"
    elif [[ $arch == aarch64* ]]; then
        arch="arm64"
    elif [[ $arch == armv7* ]]; then
        arch="armv7"
    elif [[ $arch == armv6* ]]; then
        arch="armv6"
    else
        echo -e "${red}不支持架构: ${arch}${plain}"
        exit 1
    fi
}
get_arch

echo -e "${green}系统:${release} 架构:${arch}${plain}"

install_3xui() {
    systemctl stop x-ui >/dev/null 2>&1
    cd /usr/local/

    last_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        echo -e "${red}获取3x-ui版本失败${plain}"
        exit 1
    fi
    echo -e "${green}3x-ui最新版本:${last_version}${plain}"
    wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载3x-ui失败${plain}"
        exit 1
    fi
    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}3x-ui基础安装完成${plain}"
}

install_3xui

# ========== 自定义配置部分 ==========
echo ""
echo "====================================="
echo "面板账号: $PANEL_USER"
echo "面板密码: $PANEL_PASS"
echo "面板端口: $PANEL_PORT"
echo "面板路径: $PANEL_WEB_PATH"
echo "VMess端口: $VMESS_PORT"
echo "====================================="

/usr/local/x-ui/x-ui setting -username "${PANEL_USER}" -password "${PANEL_PASS}"
/usr/local/x-ui/x-ui setting -port "${PANEL_PORT}"
/usr/local/x-ui/x-ui setting -webBasePath "${PANEL_WEB_PATH}"

x-ui restart
echo "等待3x-ui服务启动..."
sleep 8

VMESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
VMESS_ALTERID=0
CLIENT_EMAIL="auto-vmess-$(head -c8 /dev/urandom | xxd -p)"

# 获取公网IP
IP=$(curl -s --max-time 8 ifconfig.me)

# 防火墙放行
if command -v firewall-cmd &>/dev/null;then
    firewall-cmd --add-port=${PANEL_PORT}/tcp --permanent
    firewall-cmd --add-port=${VMESS_PORT}/tcp --permanent
    firewall-cmd --reload
elif command -v ufw &>/dev/null;then
    ufw allow ${PANEL_PORT}/tcp
    ufw allow ${VMESS_PORT}/tcp
fi

COOKIE_FILE=$(mktemp)
curl -s -c "$COOKIE_FILE" -X POST "http://127.0.0.1:${PANEL_PORT}/login" \
-H "Content-Type: application/json" \
-d "{\"username\":\"${PANEL_USER}\",\"password\":\"${PANEL_PASS}\"}" >/dev/null

curl -s -b "$COOKIE_FILE" -X POST "http://127.0.0.1:${PANEL_PORT}/panel/api/inbounds/add" \
-H "Content-Type: application/json" \
-d '{
"up":0,
"down":0,
"total":0,
"remark":"auto‑vmess",
"enable":true,
"expiry":0,
"listen":"",
"port":'${VMESS_PORT}',
"protocol":"vmess",
"settings":"{\"clients\":[{\"id\":\"'${VMESS_UUID}'\",\"alterId\":'${VMESS_ALTERID}',\"email\":\"'${CLIENT_EMAIL}'\"}],\"disableInsecureEncryption\":false}",
"streamSettings":"{\"network\":\"tcp\",\"security\":\"none\",\"tcpSettings\":{}}",
"sniffing":"{\"enabled\":false,\"destOverride\":[\"http\",\"tls\"]}"
}'

rm -f "$COOKIE_FILE"
x-ui restart

# 生成 vmess:// 链接
VMESS_LINK="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"auto-vmess\",\"add\":\"${IP}\",\"port\":\"${VMESS_PORT}\",\"id\":\"${VMESS_UUID}\",\"aid\":\"${VMESS_ALTERID}\",\"scy\":\"auto\",\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"none\"}" | base64 -w 0)"

echo ""
echo "====================部署完成===================="
echo "面板地址: http://${IP}:${PANEL_PORT}${PANEL_WEB_PATH}"
echo "面板账号: ${PANEL_USER}"
echo "面板密码: ${PANEL_PASS}"
echo "VMess端口: ${VMESS_PORT}"
echo "VMess UUID: ${VMESS_UUID}"
echo "alterId: ${VMESS_ALTERID}"
echo "VMess链接: ${VMESS_LINK}"
echo "================================================="
echo "⚠️云服务器安全组放行 ${PANEL_PORT}、${VMESS_PORT}"
