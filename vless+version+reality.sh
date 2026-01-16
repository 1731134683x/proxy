#!/usr/bin/env bash
set -e

################################
# 0. Root 检查
################################
if [[ $EUID -ne 0 ]]; then
  echo "请使用 root 运行"
  exit 1
fi

################################
# 1. 安装 Xray（如未安装）
################################
if ! command -v xray >/dev/null 2>&1; then
  echo "安装 Xray..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
fi

XRAY_DIR="/usr/local/etc/xray"
mkdir -p "$XRAY_DIR"

################################
# 2. 用户输入
################################
read -rp "Reality 域名（如 www.cloudflare.com）: " REALITY_DOMAIN
read -rp "监听端口（默认 443）: " PORT
PORT=${PORT:-443}

echo "IP 优先级："
echo "1) IPv4 优先（默认）"
echo "2) IPv6 优先"
read -rp "请选择 [1/2]: " IP_MODE
IP_MODE=${IP_MODE:-1}

################################
# 3. 核心参数生成（兼容性改进版）
################################
UUID=$(cat /proc/sys/kernel/random/uuid)

# 生成 8 位十六进制 Short ID
SHORT_ID=$(openssl rand -hex 4)

# 运行命令并保存完整输出
KEYS=$(xray x25519)

# 使用更灵活的匹配方式提取：忽略大小写，匹配开头的关键字
PRIVATE_KEY=$(echo "$KEYS" | grep -i "PrivateKey" | awk -F': ' '{print $2}' | tr -d ' ')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "Password" | awk -F': ' '{print $2}' | tr -d ' ')

# 如果上述方式没抓到（兼容带空格的版本）
if [[ -z "$PRIVATE_KEY" ]]; then
    PRIVATE_KEY=$(echo "$KEYS" | grep -i "Private key" | awk -F': ' '{print $2}' | tr -d ' ')
    PUBLIC_KEY=$(echo "$KEYS" | grep -i "Public key" | awk -F': ' '{print $2}' | tr -d ' ')
fi

# 严格校验
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "❌ 无法提取私钥，请检查 xray x25519 的输出格式"
  echo "当前输出为："
  echo "$KEYS"
  exit 1
fi

################################
# 4. DNS 策略
################################
if [[ "$IP_MODE" == "2" ]]; then
  DOMAIN_STRATEGY="UseIPv6"
else
  DOMAIN_STRATEGY="UseIPv4"
fi

################################
# 5. 写入配置
################################
cat >"$XRAY_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["1.1.1.1", "8.8.8.8"],
    "queryStrategy": "$DOMAIN_STRATEGY"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "outboundTag": "block",
        "ip": ["geoip:cn"]
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$REALITY_DOMAIN:443",
          "xver": 0,
          "serverNames": ["$REALITY_DOMAIN"],
          "privateKey": "$PRIVATE_KEY",
          "minClientVer": "",
          "maxClientVer": "",
          "maxTimeDiff": 0,
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

################################
# 6. 重启服务
################################
systemctl restart xray
systemctl enable xray >/dev/null 2>&1

################################
# 7. 输出信息
################################
echo
echo "======================================"
echo "Xray Reality 部署完成"
echo
echo "地址      : <你的服务器IP>"
echo "端口      : $PORT"
echo "UUID      : $UUID"
echo "流控      : xtls-rprx-vision"
echo "PublicKey : $PUBLIC_KEY"
echo "Short ID  : $SHORT_ID"
echo "SNI       : $REALITY_DOMAIN"
echo "指纹      : chrome 或 firefox"
echo "======================================"