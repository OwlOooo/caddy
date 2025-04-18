#!/bin/bash
# 改进的Caddy多域名反向代理配置脚本


# 确保以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m请使用root权限运行此脚本\033[0m"
  echo -e "用法: \033[1msudo bash $0\033[0m"
  exit 1
fi

# 定义颜色
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# 绘制分隔线
draw_line() {
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '='
}

# 函数：获取所有已配置的域名
get_configured_domains() {
  # 获取配置文件中的所有域名（仅搜索站点块的开始，格式为：example.com {）
  DOMAINS=$(grep -E '^[a-zA-Z0-9.-]+[[:space:]]*{' "$CADDY_FILE" | sed 's/{.*//' | sed 's/[[:space:]]*$//' | sort)
  echo "$DOMAINS"
}

# 脚本头部
clear
draw_line
echo -e "${BOLD}${CYAN}             Caddy 多域名反向代理配置工具${RESET}"
draw_line
echo -e "${YELLOW}此脚本可帮助您配置Caddy以提供多个域名的HTTPS反向代理${RESET}\n"

# 设置Caddy文件路径
CADDY_FILE="/etc/caddy/Caddyfile"

# 检测操作系统并安装Caddy
echo -e "${BOLD}[1/4] 检查系统要求${RESET}"
echo -e "${BLUE}检查Caddy是否已安装...${RESET}"
if ! command -v caddy &> /dev/null; then
  echo -e "${YELLOW}Caddy未安装，正在安装...${RESET}"
  
  # 检测操作系统
  if [ -f /etc/debian_version ]; then
    # Debian/Ubuntu系统
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
  elif [ -f /etc/redhat-release ]; then
    # CentOS/RHEL系统
    yum install -y yum-utils
    yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/g/caddy/caddy/repo/epel-7/group_caddy-caddy-epel-7.repo
    yum install -y caddy
  else
    echo -e "${RED}不支持的操作系统，本脚本支持Debian/Ubuntu/CentOS/RHEL${RESET}"
    echo -e "请手动安装Caddy: ${BLUE}https://caddyserver.com/docs/install${RESET}"
    exit 1
  fi
else
  echo -e "${GREEN}✓ Caddy已安装${RESET}"
fi

# 检查端口80和443是否被占用(排除caddy)
echo -e "\n${BLUE}检查端口占用情况...${RESET}"
PORT_80=$(netstat -tulpn 2>/dev/null | grep ":80 " || ss -tulpn | grep ":80 " || lsof -i:80 2>/dev/null | grep LISTEN)
PORT_443=$(netstat -tulpn 2>/dev/null | grep ":443 " || ss -tulpn | grep ":443 " || lsof -i:443 2>/dev/null | grep LISTEN)

if [ ! -z "$PORT_80" ] && ! echo "$PORT_80" | grep -q "caddy"; then
    echo -e "${YELLOW}⚠️ 端口80已被占用:${RESET}"
    echo "$PORT_80"
    echo -e "${YELLOW}Caddy需要端口80来验证Let's Encrypt证书${RESET}"
    echo -e "请考虑停止使用此端口的服务，或配置端口转发"
    read -p "$(echo -e ${BOLD}"是否继续? (y/n): "${RESET})" CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo -e "${RED}配置已取消，请释放端口80再重试${RESET}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ 端口80可用或已被Caddy使用${RESET}"
fi

if [ ! -z "$PORT_443" ] && ! echo "$PORT_443" | grep -q "caddy"; then
    echo -e "${YELLOW}⚠️ 端口443已被占用:${RESET}"
    echo "$PORT_443"
    echo -e "${YELLOW}Caddy需要端口443来提供HTTPS服务${RESET}"
    echo -e "请考虑停止使用此端口的服务"
    read -p "$(echo -e ${BOLD}"是否继续? (y/n): "${RESET})" CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo -e "${RED}配置已取消，请释放端口443再重试${RESET}"
        exit 0
    fi
else
    echo -e "${GREEN}✓ 端口443可用或已被Caddy使用${RESET}"
fi

# 创建或加载现有的Caddyfile
echo -e "\n${BOLD}[2/4] 配置文件检查${RESET}"
if [ -f "$CADDY_FILE" ]; then
    echo -e "${BLUE}检测到现有Caddyfile配置文件${RESET}"
    
    # 显示当前配置的域名
    DOMAINS=$(get_configured_domains)
    if [ ! -z "$DOMAINS" ]; then
        echo -e "${BLUE}当前已配置的域名:${RESET}"
        echo "$DOMAINS" | while read -r domain; do
            echo -e "  ${GREEN} https://$domain${RESET}"
        done
    else
        echo -e "${YELLOW}当前未配置任何域名${RESET}"
    fi
    
    # 备份现有配置
    cp "$CADDY_FILE" "$CADDY_FILE.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${GREEN}✓ 已备份现有配置到 $CADDY_FILE.bak.$(date +%Y%m%d%H%M%S)${RESET}"
    
    # 确保现有配置的末尾有换行符，这样新添加的配置会从新行开始
    sed -i -e '$a\' "$CADDY_FILE"
else
    echo -e "${BLUE}未检测到现有配置，将创建新的Caddyfile${RESET}"
    touch "$CADDY_FILE"
fi

# 选择操作
echo -e "\n${BOLD}${CYAN}┌─ 选择操作 ───────────────────────────────────────┐${RESET}"
echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
echo -e "${BOLD}${CYAN}│  ${RESET}${BOLD}1.${RESET} 添加新域名反向代理                             ${BOLD}${CYAN}│${RESET}"
echo -e "${BOLD}${CYAN}│  ${RESET}${BOLD}2.${RESET} 删除已有域名反向代理                           ${BOLD}${CYAN}│${RESET}"
echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────┘${RESET}"
read -p "$(echo -e ${BOLD}"请选择操作 [1/2]: "${RESET})" OPERATION_CHOICE

# 添加域名配置函数
add_domain_config() {
    local DOMAIN=$1
    local TARGET_PORT=$2
    
    echo -e "\n${BLUE}添加域名: ${BOLD}$DOMAIN${RESET} ${BLUE}->$TARGET_PORT${RESET}"
    
    # 检查DNS解析
    SERVER_IP=$(curl -s https://ipinfo.io/ip || curl -s https://api.ipify.org || curl -s https://icanhazip.com)
    DOMAIN_IP=$(dig +short $DOMAIN 2>/dev/null || host $DOMAIN 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    echo -e "${BLUE}服务器IP: ${RESET}$SERVER_IP"
    echo -e "${BLUE}域名解析IP: ${RESET}$DOMAIN_IP"
    
    if [ -z "$DOMAIN_IP" ]; then
        echo -e "${YELLOW}⚠️ 无法解析域名 $DOMAIN，请确保域名已正确设置${RESET}"
    elif [ "$DOMAIN_IP" = "$SERVER_IP" ]; then
        echo -e "${GREEN}✓ 域名解析正确${RESET}"
    else
        echo -e "${YELLOW}⚠️ 域名未解析到此服务器IP${RESET}"
        echo -e "${YELLOW}请确保域名 $DOMAIN 解析到 $SERVER_IP${RESET}"
    fi
    
    # 测试目标服务是否可访问
    echo -e "${BLUE}测试本地服务是否可访问...${RESET}"
    if curl -s --connect-timeout 5 "http://localhost:$TARGET_PORT" -o /dev/null; then
        echo -e "${GREEN}✓ 本地服务在端口 $TARGET_PORT 正常运行${RESET}"
    else
        echo -e "${YELLOW}⚠️ 无法连接到本地端口 $TARGET_PORT${RESET}"
        echo -e "${YELLOW}请确保您的服务在此端口正常运行${RESET}"
    fi
    
    # 检查域名是否已经存在于配置中
    if grep -q "^$DOMAIN\s*{" "$CADDY_FILE"; then
        echo -e "${YELLOW}⚠️ 域名 $DOMAIN 已存在于配置中，将更新现有配置${RESET}"
        # 删除现有配置（从域名行到下一个空行或文件末尾）
        sed -i "/^$DOMAIN\s*{/,/^$/d" "$CADDY_FILE"
    fi
    
    # 添加域名配置到Caddyfile - 不使用日志配置，避免权限问题
    cat >> "$CADDY_FILE" << EOF

# 配置域名: $DOMAIN -> localhost:$TARGET_PORT
$DOMAIN {
    # 使用自动HTTPS (Let's Encrypt)
    tls {
        protocols tls1.2 tls1.3
    }
    
    # 启用压缩
    encode gzip
    
    # 反向代理到本地服务
    reverse_proxy localhost:$TARGET_PORT {
        # 设置请求头
        header_up Host {host}
        header_up X-Real-IP {remote}
        
        # 超时设置
        transport http {
            read_timeout 300s
            write_timeout 300s
            dial_timeout 30s
        }
    }
}
EOF
    
    echo -e "${GREEN}✓ 已添加 $DOMAIN 的配置${RESET}"
}

# 删除域名配置函数
delete_domain_config() {
    # 获取所有已配置的域名
    DOMAINS=$(get_configured_domains)
    
    if [ -z "$DOMAINS" ]; then
        echo -e "${YELLOW}当前未配置任何域名${RESET}"
        return
    fi
    
    echo -e "\n${BOLD}${CYAN}┌─ 选择要删除的域名 ─────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
    
    # 显示域名列表，带有序号
    DOMAIN_ARRAY=()
    COUNTER=1
    while read -r domain; do
        DOMAIN_ARRAY+=("$domain")
        printf "${BOLD}${CYAN}│  ${RESET}${BOLD}%d.${RESET} %-46s ${BOLD}${CYAN}│${RESET}\n" $COUNTER "$domain"
        COUNTER=$((COUNTER + 1))
    done <<< "$DOMAINS"
    
    echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────┘${RESET}"
    
    read -p "$(echo -e ${BOLD}"请选择要删除的域名 [1-$((COUNTER-1))]: "${RESET})" DOMAIN_INDEX
    
    # 验证输入
    if ! [[ "$DOMAIN_INDEX" =~ ^[0-9]+$ ]] || [ "$DOMAIN_INDEX" -lt 1 ] || [ "$DOMAIN_INDEX" -gt $((COUNTER-1)) ]; then
        echo -e "${RED}选择无效，退出操作${RESET}"
        return
    fi
    
    # 获取要删除的域名
    DOMAIN_TO_DELETE="${DOMAIN_ARRAY[$((DOMAIN_INDEX-1))]}"
    
    echo -e "\n${YELLOW}即将删除域名: $DOMAIN_TO_DELETE${RESET}"
    read -p "$(echo -e ${BOLD}"确认删除? (y/n): "${RESET})" CONFIRM
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}取消删除${RESET}"
        return
    fi
    
    # 删除域名配置
    if grep -q "^$DOMAIN_TO_DELETE\s*{" "$CADDY_FILE"; then
        # 备份Caddyfile
        cp "$CADDY_FILE" "$CADDY_FILE.bak.$(date +%Y%m%d%H%M%S)"
        
        # 使用awk删除域名配置块
        awk -v domain="$DOMAIN_TO_DELETE" '
            BEGIN { skip = 0; }
            /^#/ { if (!skip) print; next; }  # 打印注释，除非在跳过的块中
            $0 ~ "^"domain"[[:space:]]*{" { skip = 1; next; }  # 开始跳过
            /^}/ { if (skip) { skip = 0; next; } }  # 结束跳过
            { if (!skip) print; }  # 打印非跳过的行
        ' "$CADDY_FILE" > "$CADDY_FILE.tmp"
        
        # 替换原文件
        mv "$CADDY_FILE.tmp" "$CADDY_FILE"
        
        echo -e "${GREEN}✓ 已删除域名 $DOMAIN_TO_DELETE 的配置${RESET}"
    else
        echo -e "${RED}错误: 找不到域名 $DOMAIN_TO_DELETE 的配置${RESET}"
    fi
}

# 根据选择执行相应操作
if [ "$OPERATION_CHOICE" = "1" ]; then
    # 添加新域名
    echo -e "\n${BOLD}[3/4] 域名配置${RESET}"
    echo -e "${BOLD}${CYAN}┌─ 输入域名信息 ─────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
    echo -e "${BOLD}${CYAN}│  ${RESET}请输入您要配置的域名和对应的本地服务端口          ${BOLD}${CYAN}│${RESET}"
    echo -e "${BOLD}${CYAN}│  ${RESET}域名将使用HTTPS协议，自动申请SSL证书             ${BOLD}${CYAN}│${RESET}"
    echo -e "${BOLD}${CYAN}│                                                  │${RESET}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────┘${RESET}"

    read -p "$(echo -e ${BOLD}"域名: "${RESET})" DOMAIN
    read -p "$(echo -e ${BOLD}"本地服务端口: "${RESET})" TARGET_PORT

    # 验证输入
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}域名不能为空，退出配置${RESET}"
        exit 1
    fi

    if ! [[ "$TARGET_PORT" =~ ^[0-9]+$ ]] || [ "$TARGET_PORT" -lt 1 ] || [ "$TARGET_PORT" -gt 65535 ]; then
        echo -e "${RED}端口必须是1-65535之间的有效数字，退出配置${RESET}"
        exit 1
    fi

    # 添加配置
    add_domain_config "$DOMAIN" "$TARGET_PORT"
elif [ "$OPERATION_CHOICE" = "2" ]; then
    # 删除域名
    echo -e "\n${BOLD}[3/4] 删除域名${RESET}"
    delete_domain_config
else
    echo -e "${RED}选择无效，退出脚本${RESET}"
    exit 1
fi

# 格式化和检查Caddy配置
echo -e "\n${BOLD}[4/4] 应用配置${RESET}"
echo -e "${BLUE}验证Caddy配置...${RESET}"
if caddy fmt --overwrite "$CADDY_FILE" 2>/dev/null && caddy validate --config "$CADDY_FILE"; then
    echo -e "${GREEN}✓ Caddy配置有效${RESET}"
else
    echo -e "${RED}⚠️ Caddy配置无效，请检查错误${RESET}"
    # 备份错误配置并退出
    cp "$CADDY_FILE" "$CADDY_FILE.error.$(date +%Y%m%d%H%M%S)"
    echo "已备份错误配置到 $CADDY_FILE.error.$(date +%Y%m%d%H%M%S)"
    exit 1
fi

# 重启Caddy服务
echo -e "${BLUE}重启Caddy服务...${RESET}"
systemctl restart caddy

# 等待几秒检查服务状态
sleep 3
if systemctl is-active --quiet caddy; then
    echo -e "${GREEN}✓ Caddy服务成功启动!${RESET}"
else
    echo -e "${RED}⚠️ Caddy服务未能启动，查看错误信息:${RESET}"
    systemctl status caddy
    echo "请查看详细日志: journalctl -u caddy"
    exit 1
fi

# 防火墙配置提示
echo -e "\n${YELLOW}如果您使用了防火墙，请确保开放了80和443端口:${RESET}"

if command -v ufw &> /dev/null; then
    echo -e "对于UFW防火墙:\n  ${BLUE}sudo ufw allow 80/tcp${RESET}\n  ${BLUE}sudo ufw allow 443/tcp${RESET}"
elif command -v firewall-cmd &> /dev/null; then
    echo -e "对于Firewalld防火墙:\n  ${BLUE}sudo firewall-cmd --permanent --add-service=http${RESET}\n  ${BLUE}sudo firewall-cmd --permanent --add-service=https${RESET}\n  ${BLUE}sudo firewall-cmd --reload${RESET}"
elif command -v iptables &> /dev/null; then
    echo -e "对于iptables防火墙:\n  ${BLUE}sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT${RESET}\n  ${BLUE}sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT${RESET}\n  ${BLUE}sudo iptables-save > /etc/iptables/rules.v4${RESET}"
fi

# 完成配置
draw_line
echo -e "${BOLD}${GREEN}        ✓ Caddy多域名反向代理配置完成!${RESET}"
draw_line

# 获取并显示所有已配置的域名
DOMAINS=$(get_configured_domains)
echo -e "\n${BOLD}${CYAN}所有已配置的域名:${RESET}"
if [ ! -z "$DOMAINS" ]; then
    echo "$DOMAINS" | while read -r domain; do
        echo -e "${GREEN}   https://$domain${RESET}"
    done
else
    echo -e "${YELLOW}  (未配置任何域名)${RESET}"
fi

echo -e "\n${BLUE}Caddy会自动处理所有域名的SSL证书申请和续期${RESET}"
echo -e "${BLUE}配置文件: $CADDY_FILE${RESET}"
echo -e "${BLUE}如需管理域名配置，请再次运行此脚本${RESET}"
draw_line
