#!/bin/bash
# ============================================================================
#  Matrix Synapse + Element + Coturn + Caddy — Автоматический установщик
#  Версия: 1.0
#  Автор: ChillGuy DevOps
#
#  Использование:
#    bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USER/matrix-installer/main/install.sh)
#
# ============================================================================

set -e

# ========================= ЦВЕТА И ФОРМАТИРОВАНИЕ ==========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ========================= УТИЛИТЫ =========================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║   ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗         ║"
    echo "║   ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝         ║"
    echo "║   ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝          ║"
    echo "║   ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗          ║"
    echo "║   ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗         ║"
    echo "║   ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝         ║"
    echo "║                                                            ║"
    echo "║   Synapse + Element + Coturn + Caddy Installer             ║"
    echo "║   v1.0                                                     ║"
    echo "║                                                            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()    { echo -e "${BLUE}[INFO]${NC}    $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
log_step()    { echo -e "\n${MAGENTA}${BOLD}▶ STEP $1: $2${NC}\n"; }

ask() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_secret="${4:-false}"

    if [ -n "$default" ]; then
        prompt="${prompt} ${DIM}[${default}]${NC}"
    fi

    if [ "$is_secret" = "true" ]; then
        echo -en "${CYAN}? ${NC}${prompt}: "
        read -s value
        echo ""
    else
        echo -en "${CYAN}? ${NC}${prompt}: "
        read value
    fi

    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi

    eval "$var_name='$value'"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    while true; do
        echo -en "${CYAN}? ${NC}${prompt} ${DIM}[${default}]${NC}: "
        read yn
        yn="${yn:-$default}"
        case "$yn" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "${RED}  Введи y или n${NC}";;
        esac
    done
}

separator() {
    echo -e "${DIM}────────────────────────────────────────────────────────${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Скрипт нужно запускать от root или через sudo"
        echo -e "  Запусти: ${BOLD}sudo bash install.sh${NC}"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Не могу определить ОС"
        exit 1
    fi
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_error "Поддерживается только Ubuntu / Debian. Твоя ОС: $ID"
        exit 1
    fi
    log_success "ОС: $PRETTY_NAME"
}

detect_ip() {
    local ip
    ip=$(curl -4 -s --max-time 5 https://ifconfig.co 2>/dev/null || \
         curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null || \
         echo "")
    echo "$ip"
}

generate_secret() {
    openssl rand -hex 32
}

generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 24
}

# ========================= ЭТАПЫ УСТАНОВКИ =================================

step_collect_params() {
    log_step "1/9" "Сбор параметров"

    echo -e "  Мне нужно задать несколько вопросов для настройки.\n"

    # --- Домен ---
    separator
    echo -e "  ${BOLD}Домены${NC}"
    echo -e "  Тебе нужны 3 поддомена, указывающие на этот сервер."
    echo ""

    ask "Основной домен (для Matrix ID, напр. example.com)" "" "DOMAIN"
    if [ -z "$DOMAIN" ]; then
        log_error "Домен обязателен!"
        exit 1
    fi

    ask "Поддомен для Synapse API" "matrix.${DOMAIN}" "MATRIX_DOMAIN"
    ask "Поддомен для Element Web" "element.${DOMAIN}" "ELEMENT_DOMAIN"
    ask "Поддомен для TURN (звонки)" "turn.${DOMAIN}" "TURN_DOMAIN"

    # --- IP ---
    separator
    echo -e "  ${BOLD}Сервер${NC}"
    local detected_ip
    detected_ip=$(detect_ip)

    ask "Внешний IP сервера" "$detected_ip" "SERVER_IP"
    if [ -z "$SERVER_IP" ]; then
        log_error "IP обязателен!"
        exit 1
    fi

    # --- Директория ---
    ask "Директория установки" "/opt/matrix" "INSTALL_DIR"

    # --- Пароли ---
    separator
    echo -e "  ${BOLD}Пароли${NC}"
    echo -e "  Оставь пустым — сгенерирую автоматически.\n"

    local auto_pg_pass auto_turn_secret
    auto_pg_pass=$(generate_password)
    auto_turn_secret=$(generate_secret)

    ask "Пароль PostgreSQL" "$auto_pg_pass" "PG_PASSWORD"
    ask "TURN shared secret" "$auto_turn_secret" "TURN_SECRET"

    # --- Admin пользователь ---
    separator
    echo -e "  ${BOLD}Admin-пользователь Matrix${NC}\n"

    ask "Имя пользователя (admin)" "admin" "ADMIN_USER"
    ask "Пароль admin-пользователя" "" "ADMIN_PASSWORD" "true"

    if [ -z "$ADMIN_PASSWORD" ]; then
        ADMIN_PASSWORD=$(generate_password)
        echo -e "  ${DIM}Сгенерирован пароль: ${ADMIN_PASSWORD}${NC}"
    fi

    # --- Firewall ---
    separator
    if ask_yes_no "Настроить UFW (firewall)?" "y"; then
        SETUP_UFW="true"
    else
        SETUP_UFW="false"
    fi

    # --- Well-known на корневом домене ---
    if ask_yes_no "Настроить .well-known на ${DOMAIN}? (для Matrix ID @user:${DOMAIN})" "y"; then
        SETUP_WELLKNOWN="true"
        echo -e "  ${YELLOW}⚠ Не забудь добавить DNS A-запись: ${DOMAIN} (корневой) → ${SERVER_IP:-IP_СЕРВЕРА}${NC}"
    else
        SETUP_WELLKNOWN="false"
    fi

    # --- Admin-панель ---
    if ask_yes_no "Установить Synapse Admin панель? (управление пользователями через веб)" "y"; then
        SETUP_ADMIN_PANEL="true"
        ask "Поддомен для Admin-панели" "admin.${DOMAIN}" "ADMIN_DOMAIN"
        echo -e "  ${DIM}Не забудь добавить DNS A-запись: ${ADMIN_DOMAIN} → ${SERVER_IP:-IP_СЕРВЕРА}${NC}"
    else
        SETUP_ADMIN_PANEL="false"
    fi

    # --- Автоочистка сообщений и медиа ---
    separator
    echo -e "  ${BOLD}Автоочистка${NC}"
    echo -e "  Можно настроить автоудаление сообщений и медиа."
    echo -e "  ${DIM}Это касается ВСЕХ комнат на сервере (по умолчанию).${NC}"
    echo -e "  ${DIM}Пользователи могут переопределить retention в настройках комнаты.${NC}"
    echo ""

    if ask_yes_no "Включить автоочистку сообщений?" "n"; then
        SETUP_RETENTION="true"
        echo ""
        echo -e "  Период хранения сообщений:"
        echo -e "  ${DIM}  1h = 1 час, 1d = 1 день, 7d = неделя, 30d = месяц, 365d = год${NC}"
        ask "Максимальный срок хранения сообщений" "7d" "RETENTION_MAX"
        ask "Минимальный срок хранения сообщений" "1h" "RETENTION_MIN"
    else
        SETUP_RETENTION="false"
    fi

    if ask_yes_no "Включить автоочистку медиафайлов?" "n"; then
        SETUP_MEDIA_PURGE="true"
        echo ""
        echo -e "  ${DIM}Медиа старше указанного срока будут удалены ежедневно в 4:00.${NC}"
        ask "Удалять медиа старше (дней)" "7" "MEDIA_PURGE_DAYS"
    else
        SETUP_MEDIA_PURGE="false"
    fi

    # --- Подтверждение ---
    separator
    echo ""
    echo -e "  ${BOLD}Конфигурация:${NC}"
    echo ""
    echo -e "  Matrix domain:     ${GREEN}${DOMAIN}${NC}"
    echo -e "  Synapse URL:       ${GREEN}https://${MATRIX_DOMAIN}${NC}"
    echo -e "  Element URL:       ${GREEN}https://${ELEMENT_DOMAIN}${NC}"
    echo -e "  TURN domain:       ${GREEN}https://${TURN_DOMAIN}${NC}"
    echo -e "  Server IP:         ${GREEN}${SERVER_IP}${NC}"
    echo -e "  Install dir:       ${GREEN}${INSTALL_DIR}${NC}"
    echo -e "  Admin user:        ${GREEN}@${ADMIN_USER}:${DOMAIN}${NC}"
    echo -e "  UFW:               ${GREEN}${SETUP_UFW}${NC}"
    echo -e "  .well-known:       ${GREEN}${SETUP_WELLKNOWN}${NC}"
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
    echo -e "  Admin панель:      ${GREEN}https://${ADMIN_DOMAIN}${NC}"
    fi
    if [ "$SETUP_RETENTION" = "true" ]; then
    echo -e "  Автоочистка чатов: ${GREEN}min=${RETENTION_MIN}, max=${RETENTION_MAX}${NC}"
    fi
    if [ "$SETUP_MEDIA_PURGE" = "true" ]; then
    echo -e "  Очистка медиа:    ${GREEN}старше ${MEDIA_PURGE_DAYS} дней${NC}"
    fi
    echo ""

    if ! ask_yes_no "Всё верно? Начинаем установку?" "y"; then
        log_warn "Отменено."
        exit 0
    fi
}

step_install_deps() {
    log_step "2/9" "Установка зависимостей"

    log_info "Обновление пакетов..."
    apt-get update -qq
    apt-get upgrade -y -qq
    log_success "Пакеты обновлены"

    log_info "Установка базовых зависимостей..."
    apt-get install -y -qq curl git jq openssl ufw apt-transport-https \
        debian-keyring debian-archive-keyring ca-certificates gnupg lsb-release > /dev/null 2>&1
    log_success "Базовые зависимости установлены"
}

step_install_docker() {
    log_step "3/9" "Установка Docker"

    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
    else
        log_info "Устанавливаю Docker..."
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        log_success "Docker установлен: $(docker --version)"
    fi

    if ! docker compose version &> /dev/null; then
        log_info "Устанавливаю Docker Compose plugin..."
        apt-get install -y -qq docker-compose-plugin > /dev/null 2>&1
    fi
    log_success "Docker Compose: $(docker compose version --short)"
}

step_install_caddy() {
    log_step "4/9" "Установка Caddy"

    if command -v caddy &> /dev/null; then
        log_success "Caddy уже установлен: $(caddy version)"
    else
        log_info "Устанавливаю Caddy..."
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
            | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null

        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
            | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

        apt-get update -qq
        apt-get install -y -qq caddy > /dev/null 2>&1
        log_success "Caddy установлен: $(caddy version)"
    fi
}

step_setup_firewall() {
    log_step "5/9" "Настройка Firewall"

    if [ "$SETUP_UFW" != "true" ]; then
        log_warn "Пропущено (UFW отключён пользователем)"
        return
    fi

    log_info "Настраиваю UFW..."
    ufw --force reset > /dev/null 2>&1
    ufw default deny incoming > /dev/null 2>&1
    ufw default allow outgoing > /dev/null 2>&1

    # SSH
    ufw allow 22/tcp > /dev/null 2>&1

    # HTTP/HTTPS
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow 443/tcp > /dev/null 2>&1

    # Federation
    ufw allow 8448/tcp > /dev/null 2>&1

    # TURN
    ufw allow 3478/tcp > /dev/null 2>&1
    ufw allow 3478/udp > /dev/null 2>&1
    ufw allow 5349/tcp > /dev/null 2>&1
    ufw allow 5349/udp > /dev/null 2>&1

    # TURN relay
    ufw allow 49152:65535/udp > /dev/null 2>&1

    ufw --force enable > /dev/null 2>&1
    log_success "UFW настроен и включён"
    log_info "Открыты порты: 22, 80, 443, 8448, 3478, 5349, 49152-65535/udp"
}

step_create_configs() {
    log_step "6/9" "Создание конфигураций"

    mkdir -p "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"

    # ---------- docker-compose.yml ----------
    log_info "docker-compose.yml..."

    cat > docker-compose.yml << DEOF
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: synapse
      POSTGRES_USER: synapse
      POSTGRES_PASSWORD: "${PG_PASSWORD}"
      POSTGRES_INITDB_ARGS: "--encoding=UTF-8 --lc-collate=C --lc-ctype=C"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U synapse"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - matrix

  synapse:
    image: matrixdotorg/synapse:latest
    restart: unless-stopped
    volumes:
      - ./synapse-data:/data
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "127.0.0.1:8008:8008"
      - "8448:8448"
    environment:
      SYNAPSE_CONFIG_PATH: /data/homeserver.yaml
    networks:
      - matrix

  element:
    image: vectorim/element-web:latest
    restart: unless-stopped
    volumes:
      - ./element-config.json:/app/config.json:ro
    ports:
      - "127.0.0.1:8080:80"
    networks:
      - matrix

  coturn:
    image: coturn/coturn:latest
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./coturn/turnserver.conf:/etc/turnserver.conf:ro

networks:
  matrix:
    driver: bridge
DEOF

    # Добавляем admin-панель если выбрано
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
        # Вставляем перед networks:
        sed -i '/^networks:/i\  synapse-admin:\n    image: ghcr.io/etkecc/synapse-admin:latest\n    restart: unless-stopped\n    volumes:\n      - ./synapse-admin-config.json:/var/public/config.json:ro\n    ports:\n      - "127.0.0.1:8081:8080"\n    networks:\n      - matrix\n' docker-compose.yml

        # Config для admin-панели (ограничиваем только наш сервер)
        cat > synapse-admin-config.json << SAEOF
{
  "restrictBaseUrl": "https://${MATRIX_DOMAIN}"
}
SAEOF
        log_success "synapse-admin добавлен в docker-compose.yml"
    fi
    log_success "docker-compose.yml"

    # ---------- Генерация Synapse конфига ----------
    log_info "Генерация конфига Synapse..."

    docker run -it --rm \
        -v "${INSTALL_DIR}/synapse-data:/data" \
        -e SYNAPSE_SERVER_NAME="${DOMAIN}" \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate > /dev/null 2>&1

    log_success "Synapse конфиг сгенерирован"

    # ---------- Патчим homeserver.yaml ----------
    log_info "Настройка homeserver.yaml..."

    local HS_CONFIG="${INSTALL_DIR}/synapse-data/homeserver.yaml"

    # Заменяем SQLite на PostgreSQL
    # Удаляем существующую секцию database
    python3 << PYEOF
import re

with open("${HS_CONFIG}", "r") as f:
    content = f.read()

# Удаляем старую секцию database (sqlite)
content = re.sub(
    r'database:\s*\n\s*name:\s*sqlite3\s*\n\s*args:\s*\n\s*database:.*?\n',
    '',
    content,
    flags=re.MULTILINE
)

# Добавляем PostgreSQL конфиг, медиа, TURN, VoIP
extra_config = """
# === PostgreSQL ===
database:
  name: psycopg2
  args:
    user: synapse
    password: "${PG_PASSWORD}"
    database: synapse
    host: postgres
    cp_min: 5
    cp_max: 10

# === Медиа ===
max_upload_size: 100M
url_preview_enabled: true
url_preview_ip_range_blacklist:
  - '127.0.0.0/8'
  - '10.0.0.0/8'
  - '172.16.0.0/12'
  - '192.168.0.0/16'
  - '100.64.0.0/10'
  - '169.254.0.0/16'
  - '::1/128'
  - 'fe80::/10'
  - 'fc00::/7'

# === TURN (звонки/видео) ===
turn_uris:
  - "turn:${TURN_DOMAIN}:3478?transport=udp"
  - "turn:${TURN_DOMAIN}:3478?transport=tcp"
turn_shared_secret: "${TURN_SECRET}"
turn_user_lifetime: 86400000
turn_allow_guests: true

# === VoIP ===
enable_voip: true

# === Регистрация ===
enable_registration: false
allow_guest_access: false
"""

# Добавляем retention если включён
retention_enabled = "${SETUP_RETENTION}"
if retention_enabled == "true":
    extra_config += """
# === Автоочистка сообщений ===
retention:
  enabled: true
  default_policy:
    min_lifetime: ${RETENTION_MIN}
    max_lifetime: ${RETENTION_MAX}
  allowed_lifetime_min: 1h
  allowed_lifetime_max: 365d
  purge_jobs:
    - longest_max_lifetime: ${RETENTION_MAX}
      interval: 1h
"""

# Добавляем в конец
content += extra_config

with open("${HS_CONFIG}", "w") as f:
    f.write(content)

print("OK")
PYEOF

    # Исправляем listener для работы за reverse proxy
    python3 << PYEOF
import re

with open("${HS_CONFIG}", "r") as f:
    content = f.read()

# Обновляем listeners чтобы добавить x_forwarded
# Ищем секцию listeners и заменяем
listeners_block = """listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false
"""

content = re.sub(
    r'listeners:\s*\n(?:\s+- .*\n|\s+\w.*\n)*',
    listeners_block,
    content,
    count=1
)

with open("${HS_CONFIG}", "w") as f:
    f.write(content)

print("OK")
PYEOF

    log_success "homeserver.yaml настроен"

    # ---------- Element Web конфиг ----------
    log_info "element-config.json..."

    cat > element-config.json << EEOF
{
  "default_server_config": {
    "m.homeserver": {
      "base_url": "https://${MATRIX_DOMAIN}",
      "server_name": "${DOMAIN}"
    }
  },
  "brand": "Element",
  "default_country_code": "RU",
  "show_labs_settings": true,
  "default_theme": "dark",
  "room_directory": {
    "servers": ["${DOMAIN}"]
  },
  "features": {
    "feature_video_rooms": true,
    "feature_group_calls": true,
    "feature_element_call_video_lobby": true
  },
  "element_call": {
    "url": "https://call.element.io",
    "use_element_call_v2": true
  },
  "setting_defaults": {
    "breadcrumbs": true
  }
}
EEOF
    log_success "element-config.json"

    # ---------- Coturn конфиг ----------
    log_info "turnserver.conf..."

    mkdir -p coturn

    cat > coturn/turnserver.conf << TEOF
# === Порты ===
listening-port=3478
listening-ip=0.0.0.0

# === Внешний IP ===
external-ip=${SERVER_IP}

# === Домен ===
realm=${TURN_DOMAIN}
server-name=${TURN_DOMAIN}

# === Аутентификация ===
use-auth-secret
static-auth-secret=${TURN_SECRET}

# === Relay ===
min-port=49152
max-port=65535

# === Безопасность ===
no-tcp-relay
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=0.0.0.0-0.0.0.255
denied-peer-ip=100.64.0.0-100.127.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255

# === Логирование ===
log-file=stdout
verbose
fingerprint
no-cli
TEOF
    log_success "turnserver.conf"

    # ---------- Caddyfile ----------
    log_info "Caddyfile..."

    local WELLKNOWN_BLOCK=""
    if [ "$SETUP_WELLKNOWN" = "true" ]; then
        WELLKNOWN_BLOCK="
# .well-known на корневом домене (Matrix ID: @user:${DOMAIN})
${DOMAIN} {
    handle /.well-known/matrix/server {
        header Content-Type application/json
        respond \`{\"m.server\": \"${MATRIX_DOMAIN}:443\"}\`
    }
    handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond \`{\"m.homeserver\": {\"base_url\": \"https://${MATRIX_DOMAIN}\"}}\`
    }
    respond \"Nothing here\" 404
}
"
    fi

    cat > /etc/caddy/Caddyfile << CEOF
# ===== Matrix Synapse =====
${MATRIX_DOMAIN} {
    reverse_proxy /_matrix/* localhost:8008
    reverse_proxy /_synapse/* localhost:8008

    handle /.well-known/matrix/server {
        header Content-Type application/json
        respond \`{"m.server": "${MATRIX_DOMAIN}:443"}\`
    }

    handle /.well-known/matrix/client {
        header Content-Type application/json
        header Access-Control-Allow-Origin *
        respond \`{"m.homeserver": {"base_url": "https://${MATRIX_DOMAIN}"}}\`
    }

    reverse_proxy localhost:8008
}

# ===== Element Web =====
${ELEMENT_DOMAIN} {
    reverse_proxy localhost:8080
}

# ===== TURN (для получения сертификата) =====
${TURN_DOMAIN} {
    respond "TURN server"
}
${WELLKNOWN_BLOCK}
CEOF

    # Добавляем admin-панель в Caddyfile если выбрано
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
        cat >> /etc/caddy/Caddyfile << CAEOF

# ===== Synapse Admin Panel =====
${ADMIN_DOMAIN} {
    reverse_proxy localhost:8081 {
        transport http {
            versions 1.1
        }
    }
}
CAEOF
    fi

    log_success "Caddyfile"

    # ---------- Скрипт очистки медиа ----------
    if [ "$SETUP_MEDIA_PURGE" = "true" ]; then
        log_info "Скрипт очистки медиа..."

        cat > "${INSTALL_DIR}/purge-media.sh" << 'PMEOF'
#!/bin/bash
# Автоочистка медиа Matrix Synapse
# Запускается по cron, удаляет медиа старше N дней

INSTALL_DIR="__INSTALL_DIR__"
PURGE_DAYS="__PURGE_DAYS__"
MATRIX_DOMAIN="__MATRIX_DOMAIN__"
ADMIN_USER="__ADMIN_USER__"
DOMAIN="__DOMAIN__"
LOG_FILE="${INSTALL_DIR}/purge-media.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"; }

# Получаем admin access token через Synapse Admin API
# Используем nonce-based registration или login
TOKEN=$(docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T synapse \
    curl -sf -X POST http://localhost:8008/_matrix/client/r0/login \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"m.login.password\",\"user\":\"${ADMIN_USER}\",\"password\":\"$(grep ADMIN_PASSWORD ${INSTALL_DIR}/.install-info | cut -d= -f2)\"}" \
    2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)

if [ -z "$TOKEN" ]; then
    log "ERROR: Не удалось получить access token"
    exit 1
fi

# Timestamp: N дней назад в миллисекундах
BEFORE_TS=$(python3 -c "import time; print(int((time.time() - ${PURGE_DAYS}*86400) * 1000))")

# Удаляем локальные медиа
RESULT=$(docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T synapse \
    curl -sf -X POST \
    "http://localhost:8008/_synapse/admin/v1/media/delete?before_ts=${BEFORE_TS}" \
    -H "Authorization: Bearer ${TOKEN}" \
    2>/dev/null)

DELETED=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")
log "Удалено медиафайлов: ${DELETED} (старше ${PURGE_DAYS} дней)"

# Удаляем кэш удалённых медиа из remote серверов
docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T synapse \
    curl -sf -X POST \
    "http://localhost:8008/_synapse/admin/v1/purge_media_cache?before_ts=${BEFORE_TS}" \
    -H "Authorization: Bearer ${TOKEN}" > /dev/null 2>&1

log "Кэш удалённых медиа очищен"
PMEOF

        # Подставляем переменные
        sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "${INSTALL_DIR}/purge-media.sh"
        sed -i "s|__PURGE_DAYS__|${MEDIA_PURGE_DAYS}|g" "${INSTALL_DIR}/purge-media.sh"
        sed -i "s|__MATRIX_DOMAIN__|${MATRIX_DOMAIN}|g" "${INSTALL_DIR}/purge-media.sh"
        sed -i "s|__ADMIN_USER__|${ADMIN_USER}|g" "${INSTALL_DIR}/purge-media.sh"
        sed -i "s|__DOMAIN__|${DOMAIN}|g" "${INSTALL_DIR}/purge-media.sh"
        chmod +x "${INSTALL_DIR}/purge-media.sh"

        # Cron: каждый день в 4:00
        (crontab -l 2>/dev/null | grep -v "purge-media.sh"; \
         echo "0 4 * * * ${INSTALL_DIR}/purge-media.sh") | crontab -

        log_success "purge-media.sh (cron: ежедневно 4:00, удаляет медиа старше ${MEDIA_PURGE_DAYS} дней)"
    fi

    # ---------- Скрипт полного удаления ----------
    log_info "uninstall.sh..."

    cat > "${INSTALL_DIR}/uninstall.sh" << 'UEOF'
#!/bin/bash
# ============================================================================
#  Matrix Synapse — Полное удаление
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="__INSTALL_DIR__"

echo -e "${RED}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              УДАЛЕНИЕ MATRIX SYNAPSE                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Это удалит ВСЁ:${NC}"
echo "  - Docker контейнеры (synapse, postgres, element, coturn, synapse-admin)"
echo "  - Все данные: база, медиа, конфиги, ключи шифрования сервера"
echo "  - Caddy конфиг и сертификаты для Matrix-доменов"
echo "  - Cron-задачи очистки"
echo "  - Директорию ${INSTALL_DIR}"
echo ""
echo -e "${RED}${BOLD}ВНИМАНИЕ: Все сообщения, медиа, пользователи будут УНИЧТОЖЕНЫ!${NC}"
echo -e "${RED}Это действие НЕОБРАТИМО!${NC}"
echo ""

read -p "Введи 'DELETE ALL' для подтверждения: " confirm
if [ "$confirm" != "DELETE ALL" ]; then
    echo -e "${GREEN}Отменено.${NC}"
    exit 0
fi

echo ""

# 1. Остановка и удаление контейнеров + volumes
echo -e "${YELLOW}[1/5]${NC} Останавливаю контейнеры..."
cd "${INSTALL_DIR}" 2>/dev/null && docker compose down -v --remove-orphans 2>/dev/null || true

# 2. Удаление Docker-образов (опционально)
read -p "Удалить Docker-образы (matrixdotorg/synapse, postgres, etc.)? [y/N]: " del_images
if [[ "$del_images" =~ ^[Yy] ]]; then
    echo -e "${YELLOW}[2/5]${NC} Удаляю Docker-образы..."
    docker rmi matrixdotorg/synapse:latest 2>/dev/null || true
    docker rmi postgres:16-alpine 2>/dev/null || true
    docker rmi vectorim/element-web:latest 2>/dev/null || true
    docker rmi coturn/coturn:latest 2>/dev/null || true
    docker rmi ghcr.io/etkecc/synapse-admin:latest 2>/dev/null || true
else
    echo -e "${YELLOW}[2/5]${NC} Docker-образы сохранены"
fi

# 3. Удаление Caddy конфига
echo -e "${YELLOW}[3/5]${NC} Очищаю Caddy конфиг..."
if [ -f /etc/caddy/Caddyfile ]; then
    # Удаляем содержимое Caddyfile (оставляем пустой)
    echo "# Caddyfile cleared after Matrix uninstall" > /etc/caddy/Caddyfile
    systemctl reload caddy 2>/dev/null || true
fi

# 4. Удаление cron-задач
echo -e "${YELLOW}[4/5]${NC} Удаляю cron-задачи..."
(crontab -l 2>/dev/null | grep -v "purge-media.sh" | grep -v "copy-turn-certs.sh") | crontab - 2>/dev/null || true

# 5. Удаление директории
echo -e "${YELLOW}[5/5]${NC} Удаляю ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}"

echo ""
echo -e "${GREEN}${BOLD}Удаление завершено!${NC}"
echo ""
echo "  Что осталось на сервере (не удалялось):"
echo "  - Docker Engine"
echo "  - Caddy (пустой конфиг)"
echo "  - UFW правила"
echo ""
echo "  Для переустановки:"
echo "  bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USER/matrix-installer/main/install.sh)"
echo ""
UEOF

    sed -i "s|__INSTALL_DIR__|${INSTALL_DIR}|g" "${INSTALL_DIR}/uninstall.sh"
    chmod +x "${INSTALL_DIR}/uninstall.sh"
    log_success "uninstall.sh"
}

step_start_services() {
    log_step "7/9" "Запуск сервисов"

    cd "${INSTALL_DIR}"

    # Caddy
    log_info "Запускаю Caddy..."
    # Чистим staging-сертификаты (на случай повторного запуска)
    rm -rf /var/lib/caddy/.local/share/caddy/certificates/acme-staging* 2>/dev/null
    rm -rf /var/lib/caddy/.local/share/caddy/locks 2>/dev/null
    systemctl restart caddy
    systemctl enable caddy > /dev/null 2>&1
    sleep 3

    if systemctl is-active --quiet caddy; then
        log_success "Caddy запущен (SSL сертификаты получаются автоматически)"
    else
        log_error "Caddy не запустился! Проверь: journalctl -u caddy -f"
        log_warn "Возможная причина: DNS ещё не пропагировался на домены"
    fi

    # Docker containers
    log_info "Запускаю Docker контейнеры..."
    docker compose pull --quiet
    docker compose up -d

    log_info "Жду пока Synapse инициализируется (30 сек)..."
    sleep 30

    # Проверка
    local synapse_ok=false
    for i in {1..10}; do
        if curl -sf http://localhost:8008/_matrix/client/versions > /dev/null 2>&1; then
            synapse_ok=true
            break
        fi
        sleep 5
    done

    if [ "$synapse_ok" = "true" ]; then
        log_success "Synapse запущен и отвечает"
    else
        log_error "Synapse не отвечает. Проверь логи: docker compose logs synapse"
    fi

    # Проверка coturn
    if ss -tulnp | grep -q ':3478'; then
        log_success "Coturn запущен (порт 3478)"
    else
        log_warn "Coturn не слушает порт 3478. Проверь: docker compose logs coturn"
    fi
}

step_create_admin() {
    log_step "8/9" "Создание admin-пользователя"

    cd "${INSTALL_DIR}"

    log_info "Создаю пользователя @${ADMIN_USER}:${DOMAIN}..."

    docker compose exec -T synapse register_new_matrix_user \
        http://localhost:8008 \
        -c /data/homeserver.yaml \
        --user "${ADMIN_USER}" \
        --password "${ADMIN_PASSWORD}" \
        --admin 2>&1 || {
            log_warn "Не удалось создать пользователя автоматически."
            log_info "Создай вручную:"
            echo -e "  ${DIM}cd ${INSTALL_DIR}${NC}"
            echo -e "  ${DIM}docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml${NC}"
        }

    log_success "Admin-пользователь создан"
}

step_final_check() {
    log_step "9/9" "Финальная проверка"

    local all_ok=true

    # Synapse API
    if curl -sf "http://localhost:8008/_matrix/client/versions" > /dev/null 2>&1; then
        log_success "Synapse API         ✓"
    else
        log_error "Synapse API         ✗"
        all_ok=false
    fi

    # Element Web
    if curl -sf "http://localhost:8080" > /dev/null 2>&1; then
        log_success "Element Web         ✓"
    else
        log_error "Element Web         ✗"
        all_ok=false
    fi

    # Caddy
    if systemctl is-active --quiet caddy; then
        log_success "Caddy               ✓"
    else
        log_error "Caddy               ✗"
        all_ok=false
    fi

    # Coturn
    if ss -tulnp | grep -q ':3478'; then
        log_success "Coturn              ✓"
    else
        log_error "Coturn              ✗"
        all_ok=false
    fi

    # PostgreSQL
    if docker compose -f "${INSTALL_DIR}/docker-compose.yml" exec -T postgres pg_isready -U synapse > /dev/null 2>&1; then
        log_success "PostgreSQL          ✓"
    else
        log_error "PostgreSQL          ✗"
        all_ok=false
    fi

    # HTTPS check
    if curl -sf "https://${MATRIX_DOMAIN}/_matrix/client/versions" > /dev/null 2>&1; then
        log_success "HTTPS (Synapse)     ✓"
    else
        log_warn "HTTPS (Synapse)     ~ (SSL может ещё генерироваться)"
    fi

    # Admin Panel
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
        if curl -sf "http://localhost:8081" > /dev/null 2>&1; then
            log_success "Synapse Admin       ✓"
        else
            log_warn "Synapse Admin       ~ (может ещё запускаться)"
        fi
    fi

    separator
    echo ""

    if [ "$all_ok" = "true" ]; then
        echo -e "${GREEN}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                  УСТАНОВКА ЗАВЕРШЕНА!                      ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    else
        echo -e "${YELLOW}${BOLD}"
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║          УСТАНОВКА ЗАВЕРШЕНА (с предупреждениями)           ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi

    echo -e "  ${BOLD}Доступ:${NC}"
    echo ""
    echo -e "  Element Web:      ${GREEN}https://${ELEMENT_DOMAIN}${NC}"
    echo -e "  Synapse API:      ${GREEN}https://${MATRIX_DOMAIN}${NC}"
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
    echo -e "  Admin панель:     ${GREEN}https://${ADMIN_DOMAIN}${NC}"
    fi
    echo -e "  Matrix ID:        ${GREEN}@${ADMIN_USER}:${DOMAIN}${NC}"
    echo ""
    echo -e "  ${BOLD}Логин:${NC}"
    echo -e "  Имя:              ${CYAN}${ADMIN_USER}${NC}"
    echo -e "  Пароль:           ${CYAN}${ADMIN_PASSWORD}${NC}"
    echo ""
    echo -e "  ${BOLD}Клиенты:${NC}"
    echo -e "  Android:          ${DIM}https://play.google.com/store/apps/details?id=im.vector.app${NC}"
    echo -e "  iOS:              ${DIM}https://apps.apple.com/app/element-messenger/id1083446067${NC}"
    echo -e "  macOS:            ${DIM}brew install --cask element${NC}"
    echo ""
    echo -e "  ${BOLD}При входе в клиенте:${NC}"
    echo -e "  Homeserver URL → ${GREEN}https://${MATRIX_DOMAIN}${NC}"
    echo ""
    if [ "$SETUP_ADMIN_PANEL" = "true" ]; then
    echo -e "  ${BOLD}Admin-панель (https://${ADMIN_DOMAIN}):${NC}"
    echo -e "  Логин admin-аккаунтом Matrix. Можно: создавать/удалять"
    echo -e "  пользователей, сбрасывать пароли, управлять комнатами и медиа."
    echo -e "  ${DIM}E2E-зашифрованные чаты прочитать невозможно — даже из-под админа.${NC}"
    echo ""
    fi
    separator
    echo ""
    echo -e "  ${BOLD}Полезные команды:${NC}"
    echo ""
    echo -e "  ${DIM}# Логи${NC}"
    echo -e "  cd ${INSTALL_DIR} && docker compose logs -f"
    echo ""
    echo -e "  ${DIM}# Новый пользователь${NC}"
    echo -e "  cd ${INSTALL_DIR} && docker compose exec synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml"
    echo ""
    echo -e "  ${DIM}# Обновление${NC}"
    echo -e "  cd ${INSTALL_DIR} && docker compose pull && docker compose up -d"
    echo ""
    echo -e "  ${DIM}# Бэкап БД${NC}"
    echo -e "  cd ${INSTALL_DIR} && docker compose exec postgres pg_dump -U synapse synapse > backup.sql"
    echo ""
    if [ "$SETUP_MEDIA_PURGE" = "true" ]; then
    echo -e "  ${DIM}# Ручная очистка медиа (cron уже настроен на 4:00)${NC}"
    echo -e "  ${INSTALL_DIR}/purge-media.sh"
    echo ""
    fi
    echo -e "  ${DIM}# Полное удаление (удалит ВСЁ!)${NC}"
    echo -e "  ${INSTALL_DIR}/uninstall.sh"
    echo ""
    separator

    # Сохраняем данные в файл
    cat > "${INSTALL_DIR}/.install-info" << IEOF
# Matrix Install Info ($(date))
# СОХРАНИ ЭТОТ ФАЙЛ В БЕЗОПАСНОМ МЕСТЕ И УДАЛИ С СЕРВЕРА

DOMAIN=${DOMAIN}
MATRIX_DOMAIN=${MATRIX_DOMAIN}
ELEMENT_DOMAIN=${ELEMENT_DOMAIN}
TURN_DOMAIN=${TURN_DOMAIN}
SERVER_IP=${SERVER_IP}
PG_PASSWORD=${PG_PASSWORD}
TURN_SECRET=${TURN_SECRET}
ADMIN_USER=${ADMIN_USER}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
SETUP_ADMIN_PANEL=${SETUP_ADMIN_PANEL}
ADMIN_DOMAIN=${ADMIN_DOMAIN:-none}
SETUP_RETENTION=${SETUP_RETENTION:-false}
RETENTION_MAX=${RETENTION_MAX:-none}
SETUP_MEDIA_PURGE=${SETUP_MEDIA_PURGE:-false}
MEDIA_PURGE_DAYS=${MEDIA_PURGE_DAYS:-none}
IEOF
    chmod 600 "${INSTALL_DIR}/.install-info"

    echo ""
    log_warn "Данные установки сохранены в ${INSTALL_DIR}/.install-info"
    log_warn "Скопируй их в безопасное место и удали файл с сервера!"
    echo ""
}

# ========================= ГЛАВНАЯ ФУНКЦИЯ =================================

main() {
    # Обработка флагов
    case "${1:-}" in
        --uninstall|uninstall|--remove|remove)
            check_root
            local install_dir="/opt/matrix"
            if [ -f "${install_dir}/uninstall.sh" ]; then
                bash "${install_dir}/uninstall.sh"
            else
                echo -e "${RED}Скрипт удаления не найден в ${install_dir}/uninstall.sh${NC}"
                echo "Укажи директорию: $0 --uninstall /path/to/matrix"
            fi
            exit 0
            ;;
        --purge-media|purge-media)
            check_root
            local install_dir="/opt/matrix"
            if [ -f "${install_dir}/purge-media.sh" ]; then
                bash "${install_dir}/purge-media.sh"
                echo "Готово. Лог: ${install_dir}/purge-media.log"
            else
                echo "Скрипт очистки не найден. Автоочистка медиа не была настроена."
            fi
            exit 0
            ;;
        --help|-h|help)
            echo "Matrix Synapse Installer"
            echo ""
            echo "Использование:"
            echo "  sudo bash install.sh              — установка (интерактивный визард)"
            echo "  sudo bash install.sh --uninstall   — полное удаление"
            echo "  sudo bash install.sh --purge-media — ручная очистка медиа"
            echo "  sudo bash install.sh --help        — эта справка"
            exit 0
            ;;
    esac

    clear
    print_banner
    check_root
    check_os
    echo ""

    step_collect_params
    step_install_deps
    step_install_docker
    step_install_caddy
    step_setup_firewall
    step_create_configs
    step_start_services
    step_create_admin
    step_final_check
}

main "$@"