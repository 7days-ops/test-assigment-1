#!/bin/bash

# healthcheck.sh - Скрипт мониторинга Flask приложения в Docker
# Использование: ./healthcheck.sh
# Cron: */10 * * * * /path/to/Scripts/healthcheck.sh >> /var/log/healthcheck-cron.log 2>&1

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && cd .. && pwd)"
APP_DIR="${PROJECT_ROOT}/flask-auth-example"
CONTAINER_NAME="flask-application"  # ← Имя вашего контейнера

# Загрузка .env
if [ -f "${APP_DIR}/.env" ]; then
    # Безопасная загрузка (защищает от спецсимволов)
    set -a
    source <(grep -v '^#' "${APP_DIR}/.env" | sed 's/ *= */=/g')
    set +a
fi

# URL приложения (должен быть доступен с хоста)
APP_URL="http://localhost:5000"
REGISTER_ENDPOINT="${APP_URL}/register"

# Логи
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/healthcheck.log"
ALERT_LOG="${LOG_DIR}/healthcheck_alerts.log"

DISK_THRESHOLD=80
RESPONSE_TIME_THRESHOLD=5

mkdir -p "${LOG_DIR}"

log() {
    local level=$1; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >> "${LOG_FILE}"
}

alert() {
    local msg="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ALERT: ${msg}" >> "${ALERT_LOG}"
    if [ -n "${ALERT_EMAIL:-}" ]; then
        echo "$msg" | mail -s "Flask App Health Alert" "$ALERT_EMAIL" 2>/dev/null || true
    fi
}


check_docker_container() {
    log "INFO" "Проверка состояния Docker-контейнера '${CONTAINER_NAME}'..."

    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker не установлен на хосте"
        alert "Docker не найден — невозможно проверить контейнер"
        return 1
    fi

    if docker ps -f "name=${CONTAINER_NAME}" -f "status=running" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        local id=$(docker inspect --format='{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null | cut -c1-12)
        log "INFO" "Контейнер запущен (ID: ${id})"
        return 0
    else
        log "ERROR" "Контейнер '${CONTAINER_NAME}' не запущен или не существует"
        alert "Docker-контейнер '${CONTAINER_NAME}' не активен"
        return 1
    fi
}

# Проверка HTTP (без изменений — работает, если порт проброшен)
check_http_status() {
    log "INFO" "Проверка HTTP статуса (${APP_URL})..."
    local start_time=$(date +%s)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${APP_URL}" 2>/dev/null || echo "000")
    local end_time=$(date +%s)
    local response_time=$((end_time - start_time))

    if [[ "$http_code" == "200" || "$http_code" == "302" ]]; then
        log "INFO" "HTTP: ${http_code} (OK), время: ${response_time}s"
        if (( response_time > RESPONSE_TIME_THRESHOLD )); then
            alert "Медленный ответ: ${response_time}s (порог: ${RESPONSE_TIME_THRESHOLD}s)"
        fi
        return 0
    else
        log "ERROR" "HTTP: ${http_code} (FAILED)"
        alert "Веб-сервер недоступен. HTTP код: ${http_code}"
        return 1
    fi
}

check_app_endpoint() {
    log "INFO" "Проверка эндпоинта /register..."
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${REGISTER_ENDPOINT}" 2>/dev/null || echo "000")
    if [ "$http_code" = "200" ]; then
        log "INFO" "/register доступен (HTTP ${http_code})"
        return 0
    else
        log "ERROR" "/register недоступен (HTTP ${http_code})"
        alert "Эндпоинт /register недоступен. HTTP код: ${http_code}"
        return 1
    fi
}

# Проверка БД — без изменений (если БД на хосте или в отдельном контейнере с пробросом порта)
check_database() {
    log "INFO" "Проверка подключения к PostgreSQL..."
    if [ -z "${DB_HOST:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_NAME:-}" ]; then
        log "ERROR" "Переменные БД не заданы"
        alert "Не заданы переменные окружения PostgreSQL"
        return 1
    fi

    if command -v psql &> /dev/null; then
        local out=$(PGPASSWORD="${DB_PASSWORD:-}" psql -h "${DB_HOST}" -p "${DB_PORT:-5432}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" -t 2>&1)
        if [ $? -eq 0 ]; then
            log "INFO" "PostgreSQL: OK (${DB_HOST}:${DB_PORT:-5432})"
            return 0
        else
            log "ERROR" "PostgreSQL ошибка: $out"
            alert "Не удалось подключиться к PostgreSQL"
            return 1
        fi
    else
        log "WARNING" "psql не установлен, проверка БД пропущена"
        return 0
    fi
}

check_disk_space() {
    local usage=$(df / --output=pcent | tail -1 | tr -d ' %')
    log "INFO" "Использование диска: ${usage}%"
    if (( usage > DISK_THRESHOLD )); then
        log "WARNING" "Высокое использование диска: ${usage}%"
        alert "Диск заполнен на ${usage}% (порог: ${DISK_THRESHOLD}%)"
        return 1
    fi
    return 0
}

# Логи: если логи монтируются на хост — ок, иначе пропустить
check_logs() {
    local app_log="${APP_DIR}/logs/app.log"
    if [ -f "$app_log" ]; then
        local errors=$(tail -100 "$app_log" 2>/dev/null | grep -i -c "error\|critical\|exception" || echo 0)
        log "INFO" "Ошибок в логах: ${errors}"
        if (( errors > 10 )); then
            alert "Обнаружено ${errors} ошибок в логах"
        fi
    else
        log "INFO" "Лог-файл не найден (возможно, не смонтирован из контейнера)"
    fi
}




generate_report() {
    local status=$1
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    cat <<EOF

========================================
Flask Application Health Check Report
========================================
Время проверки: ${ts}
Общий статус: ${status}
========================================

EOF
}

main() {
    log "INFO" "========== Начало проверки здоровья (Docker-режим) =========="

    local all_ok=true
    local fails=()


    check_docker_container || { all_ok=false; fails+=("docker_container"); }
    sleep 1

    check_http_status || { all_ok=false; fails+=("http_status"); }
    sleep 1

    check_app_endpoint || { all_ok=false; fails+=("app_endpoint"); }
    sleep 1

    check_database || { all_ok=false; fails+=("database"); }
    check_disk_space || { all_ok=false; fails+=("disk_space"); }
    check_logs

    if [ "$all_ok" = true ]; then
        log "INFO" "Все проверки пройдены успешно ✓"
        generate_report "HEALTHY" >> "${LOG_FILE}"
        exit 0
    else
        log "ERROR" "Проваленные проверки: ${fails[*]}"
        generate_report "UNHEALTHY" >> "${LOG_FILE}"
        alert "Healthcheck failed. Провалено: ${fails[*]}"
        exit 1
    fi
}

main "$@"
