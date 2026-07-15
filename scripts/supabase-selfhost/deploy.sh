#!/bin/bash
# ============================================================
# Supabase 自托管一键部署脚本（精简版 + 域名 HTTPS）
# 适用于：Ubuntu 20.04 / 22.04 / 24.04
# 组件：PostgreSQL + PostgREST + Kong + Auth + Studio + Meta
# 精简：移除 Realtime / Storage / imgproxy / Edge Functions / Analytics
# ============================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# 第一步：检查系统
# ============================================================
check_system() {
    log_info "检查系统环境..."
    
    if [ "$(id -u)" -ne 0 ]; then
        log_error "请使用 root 权限运行：sudo bash $0"
        exit 1
    fi
    
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        log_info "操作系统: $PRETTY_NAME"
    else
        log_warn "无法识别操作系统，假设是 Ubuntu/Debian"
        OS="ubuntu"
    fi
    
    # 检查内存
    MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
    log_info "内存总量: ${MEM_TOTAL}MB"
    if [ "$MEM_TOTAL" -lt 2000 ]; then
        log_warn "内存不足 2GB，可能跑不起来，建议至少 4GB"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    # 检查磁盘
    DISK_FREE=$(df -m / | awk 'NR==2{print $4}')
    log_info "磁盘剩余: ${DISK_FREE}MB"
    if [ "$DISK_FREE" -lt 10000 ]; then
        log_warn "磁盘不足 10GB，建议至少 50GB"
    fi
}

# ============================================================
# 第二步：安装 Docker & Docker Compose
# ============================================================
install_docker() {
    if command -v docker &> /dev/null; then
        log_info "Docker 已安装: $(docker --version)"
    else
        log_info "安装 Docker..."
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg lsb-release
        
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
        log_info "Docker 安装完成"
    fi
    
    if docker compose version &> /dev/null; then
        log_info "Docker Compose 已安装: $(docker compose version)"
    else
        log_error "Docker Compose 安装失败"
        exit 1
    fi
}

# ============================================================
# 第三步：下载 Supabase Docker 配置
# ============================================================
download_supabase() {
    INSTALL_DIR="/opt/supabase"
    
    if [ -d "$INSTALL_DIR" ]; then
        log_warn "安装目录 $INSTALL_DIR 已存在"
        read -p "是否覆盖重新安装？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd $INSTALL_DIR
            docker compose down 2>/dev/null || true
            cd /
            rm -rf $INSTALL_DIR
        else
            log_info "跳过下载，使用现有配置"
            return
        fi
    fi
    
    log_info "下载 Supabase Docker 配置..."
    mkdir -p $INSTALL_DIR
    
    cd /tmp
    if [ -d "supabase-repo" ]; then
        rm -rf supabase-repo
    fi
    
    git clone --depth 1 https://github.com/supabase/supabase.git supabase-repo 2>/dev/null || {
        log_error "克隆失败，请检查网络（可能需要代理）"
        exit 1
    }
    
    cp -r supabase-repo/docker/* $INSTALL_DIR/
    cp supabase-repo/docker/.env.example $INSTALL_DIR/.env
    rm -rf supabase-repo
    
    log_info "配置文件已下载到 $INSTALL_DIR"
}

# ============================================================
# 第四步：生成密钥 & 配置 .env
# ============================================================
configure_env() {
    INSTALL_DIR="/opt/supabase"
    cd $INSTALL_DIR
    
    log_info "生成安全密钥..."
    
    # 生成关键密码
    POSTGRES_PASSWORD=$(openssl rand -hex 24)
    JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')
    DASHBOARD_PASSWORD=$(openssl rand -hex 12)
    
    # 获取服务器公网 IP
    SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "your-server-ip")
    log_info "服务器 IP: $SERVER_IP"
    
    # 交互式配置
    echo ""
    read -p "请输入 Supabase 子域名（如 api.cn07.cn）: " DOMAIN
    if [ -z "$DOMAIN" ]; then
        log_error "域名不能为空"
        exit 1
    fi
    
    PUBLIC_URL="https://$DOMAIN"
    log_info "公网地址: $PUBLIC_URL"
    
    read -p "请设置 Dashboard 用户名（默认 supabase）: " DASHBOARD_USER
    DASHBOARD_USER=${DASHBOARD_USER:-supabase}
    
    read -p "请设置 Dashboard 密码（自动生成：$DASHBOARD_PASSWORD）: " DASHBOARD_PWD
    DASHBOARD_PWD=${DASHBOARD_PWD:-$DASHBOARD_PASSWORD}
    
    # 更新 .env 关键配置
    log_info "更新配置文件..."
    
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
    sed -i "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=$DASHBOARD_USER|" .env
    sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PWD|" .env
    sed -i "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=$PUBLIC_URL|" .env
    sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=$PUBLIC_URL|" .env
    sed -i "s|^SITE_URL=.*|SITE_URL=$PUBLIC_URL|" .env
    sed -i "s|^# SUPABASE_PUBLIC_URL=|SUPABASE_PUBLIC_URL=|" .env
    
    # 保存配置信息
    cat > /root/supabase-credentials.txt << EOF
========== Supabase 自托管凭据 ==========
安装目录: $INSTALL_DIR
公网地址: $PUBLIC_URL
域名: $DOMAIN
服务器 IP: $SERVER_IP

Dashboard 登录:
  用户名: $DASHBOARD_USER
  密码: $DASHBOARD_PWD

数据库:
  密码: $POSTGRES_PASSWORD

JWT 密钥: $JWT_SECRET

API 密钥请在 .env 文件中查看：
  cat $INSTALL_DIR/.env | grep -E "ANON_KEY|SERVICE_ROLE_KEY"

===== 常用命令 =====
启动: cd $INSTALL_DIR && docker compose up -d
停止: cd $INSTALL_DIR && docker compose down
状态: cd $INSTALL_DIR && docker compose ps
日志: cd $INSTALL_DIR && docker compose logs -f
=========================================
EOF
    
    log_info "凭据已保存到 /root/supabase-credentials.txt"
}

# ============================================================
# 第五步：精简 docker-compose.yml
# ============================================================
slim_down_compose() {
    INSTALL_DIR="/opt/supabase"
    cd $INSTALL_DIR
    
    log_info "精简 docker-compose.yml（移除不需要的组件）..."
    
    cp docker-compose.yml docker-compose.yml.bak
    
    cat > docker-compose.slim.yml << 'EOF'
# 精简版覆盖配置 - 禁用不需要的服务
# 使用方式：已默认加入 .env 的 COMPOSE_FILE

services:
  realtime:
    profiles:
      - optional
  storage:
    profiles:
      - optional
  imgproxy:
    profiles:
      - optional
  edge-runtime:
    profiles:
      - optional
  analytics:
    profiles:
      - optional
  vector:
    profiles:
      - optional
  logflare:
    profiles:
      - optional
EOF
    
    # 把精简配置加入 COMPOSE_FILE，这样 docker compose 命令默认就生效
    if grep -q "^COMPOSE_FILE=" .env; then
        sed -i "s|^COMPOSE_FILE=.*|COMPOSE_FILE=docker-compose.yml:docker-compose.slim.yml|" .env
    else
        echo "" >> .env
        echo "# 精简版配置（禁用不需要的服务）" >> .env
        echo "COMPOSE_FILE=docker-compose.yml:docker-compose.slim.yml" >> .env
    fi
    
    log_info "精简配置已生效（默认禁用 realtime/storage/imgproxy/edge-runtime/analytics/vector/logflare）"
}

# ============================================================
# 第六步：配置 Nginx 反向代理 + HTTPS
# ============================================================
configure_nginx() {
    INSTALL_DIR="/opt/supabase"
    DOMAIN=$(grep "域名:" /root/supabase-credentials.txt | awk '{print $2}')
    
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "your-server-ip" ]; then
        log_warn "未配置有效域名，跳过 Nginx + HTTPS 配置"
        return
    fi
    
    read -p "是否配置 Nginx 反向代理 + HTTPS？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        return
    fi
    
    log_info "安装 Nginx 和 certbot..."
    apt-get install -y -qq nginx certbot python3-certbot-nginx
    
    log_info "配置 Nginx 反向代理..."
    
    cat > /etc/nginx/sites-available/supabase << EOF
server {
    listen 80;
    server_name $DOMAIN;

    # 上传文件大小限制
    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持（realtime 需要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 超时时间
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
    
    # 测试配置
    nginx -t && systemctl reload nginx
    log_info "Nginx 配置完成"
    
    # 申请 SSL 证书
    read -p "是否现在申请 Let's Encrypt SSL 证书？(Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        log_info "申请 SSL 证书..."
        certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email || {
            log_warn "证书申请失败，请确认 DNS 解析已生效后手动运行："
            log_warn "  certbot --nginx -d $DOMAIN"
        }
        log_info "HTTPS 配置完成: https://$DOMAIN"
    fi
}

# ============================================================
# 第七步：配置自动备份
# ============================================================
configure_backup() {
    INSTALL_DIR="/opt/supabase"
    
    read -p "是否配置数据库自动备份？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        return
    fi
    
    log_info "配置数据库自动备份..."
    
    mkdir -p $INSTALL_DIR/backups
    
    cat > $INSTALL_DIR/backup.sh << 'BACKUPEOF'
#!/bin/bash
# Supabase 数据库自动备份脚本
BACKUP_DIR="/opt/supabase/backups"
mkdir -p $BACKUP_DIR

DATE=$(date +%Y%m%d_%H%M%S)
docker exec supabase-db pg_dump -U postgres postgres | gzip > $BACKUP_DIR/supabase_${DATE}.sql.gz

# 只保留最近 7 天的备份
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete

echo "[$(date)] 备份完成: supabase_${DATE}.sql.gz" >> $BACKUP_DIR/backup.log
BACKUPEOF
    
    chmod +x $INSTALL_DIR/backup.sh
    
    # 添加定时任务（每天凌晨 3 点）
    (crontab -l 2>/dev/null | grep -v "supabase/backup.sh"; echo "0 3 * * * /opt/supabase/backup.sh") | crontab -
    
    log_info "自动备份已配置：每天凌晨 3 点备份，保留 7 天"
    log_info "备份目录: $INSTALL_DIR/backups/"
    
    # 手动跑一次验证
    log_info "执行首次备份验证..."
    bash $INSTALL_DIR/backup.sh
}

# ============================================================
# 第八步：启动 Supabase
# ============================================================
start_supabase() {
    INSTALL_DIR="/opt/supabase"
    cd $INSTALL_DIR
    
    read -p "是否立即启动 Supabase？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ -n $REPLY ]]; then
        log_info "稍后手动启动："
        log_info "  cd $INSTALL_DIR && docker compose up -d"
        return
    fi
    
    log_info "拉取 Docker 镜像（首次可能需要 5-10 分钟）..."
    docker compose pull
    
    log_info "启动 Supabase 服务..."
    docker compose up -d --wait 2>/dev/null || docker compose up -d
    
    # 等待服务启动
    log_info "等待服务启动（约 1-2 分钟）..."
    sleep 30
    
    echo ""
    echo "=========================================="
    echo "  ✅ Supabase 部署完成！"
    echo "=========================================="
    echo ""
    echo "访问地址: $(grep "^SUPABASE_PUBLIC_URL=" .env | cut -d= -f2)"
    echo ""
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps
    echo ""
    echo "📋 凭据文件: /root/supabase-credentials.txt"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo ""
    echo "============================================"
    echo "  Supabase 自托管一键部署（精简版）"
    echo "============================================"
    echo ""
    
    check_system
    install_docker
    download_supabase
    configure_env
    slim_down_compose
    configure_nginx
    configure_backup
    start_supabase
    
    echo ""
    log_info "部署完成！有问题查看凭据文件：cat /root/supabase-credentials.txt"
}

main "$@"
