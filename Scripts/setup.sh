#!/bin/bash


set -e

LOG_PREFIX="[$(date +'%Y-%m-%d %H:%M:%S')]"

echo "$LOG_PREFIX [INFO] Начало установки"


echo "$LOG_PREFIX [INFO] Обновление списка пакетов..."
sudo apt update -y


echo "$LOG_PREFIX [INFO] Установка Python 3.12, venv, pip и зависимостей PostgreSQL..."
sudo apt install -y python3.12 python3.12-venv python3-pip python3.12-dev \
    postgresql-client libpq-dev build-essential


echo "$LOG_PREFIX [INFO] Проверка наличия python3.12..."
if command -v python3.12 &> /dev/null; then
    PYTHON_VERSION=$(python3.12 --version 2>&1 | awk '{print $2}')
    echo "Python найден: $PYTHON_VERSION"
    echo "$LOG_PREFIX [INFO] Python найден: $PYTHON_VERSION"
else
    echo "$LOG_PREFIX [ERROR] python3.12 не найден после установки. Проверьте репозитории."
    exit 1
fi


echo "$LOG_PREFIX [INFO] Проверка наличия pip3..."
if command -v pip3 &> /dev/null; then
    echo "✓ pip3 уже установлен"
else
    echo "✗ pip3 не найден. Устанавливаю python3-pip..."
    sudo apt install -y python3-pip
    echo "✓ pip3 успешно установлен"
fi


echo "$LOG_PREFIX [INFO] Проверка наличия модуля venv для python3.12..."
python3.12 -m venv --help > /dev/null 2>&1 || {
    echo "✗ Модуль venv недоступен. Устанавливаю python3.12-venv..."
    sudo apt install -y python3.12-venv
    echo "✓ python3.12-venv установлен"
}


PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
APP_DIR="${PROJECT_ROOT}/flask-auth-example"

echo "$LOG_PREFIX [INFO] Директория проекта: $APP_DIR"


if [ ! -f "${APP_DIR}/requirements.txt" ]; then
    echo "$LOG_PREFIX [ERROR] Файл requirements.txt не найден в ${APP_DIR}"
    exit 1
fi


VENV_DIR="${APP_DIR}/venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "$LOG_PREFIX [INFO] Создание виртуального окружения в $VENV_DIR..."
    python3.12 -m venv "$VENV_DIR"
    echo "✓ Виртуальное окружение создано"
else
    echo "✓ Виртуальное окружение уже существует ($VENV_DIR)"
fi


source "$VENV_DIR/bin/activate"


echo "$LOG_PREFIX [INFO] Обновление pip в виртуальном окружении..."
pip install --upgrade pip


echo "$LOG_PREFIX [INFO] Установка зависимостей из requirements.txt..."
pip install -r "${APP_DIR}/requirements.txt"
echo "✓ Зависимости установлены"


echo "$LOG_PREFIX [INFO] Проверка критических пакетов..."
for package in Flask Flask-SQLAlchemy psycopg2-binary gunicorn; do
    if pip list | grep -q "^${package} "; then
        echo "  ✓ $package установлен"
    else
        echo "  ✗ $package НЕ установлен!"
    fi
done


if [ -f "${APP_DIR}/.env" ]; then
    echo "$LOG_PREFIX [INFO] Проверка подключения к PostgreSQL..."
    source "${APP_DIR}/.env"

    if command -v psql &> /dev/null; then
        PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT version();" &> /dev/null && {
            echo "✓ Подключение к PostgreSQL успешно"
        } || {
            echo "✗ Не удалось подключиться к PostgreSQL. Проверьте настройки в .env"
        }
    else
        echo "psql не установлен, пропускаю проверку БД"
    fi
fi

echo "======================================"
echo "   Установка завершена успешно!"
echo "   Активируйте окружение: source $VENV_DIR/bin/activate"
echo "   Запуск приложения: cd $APP_DIR && gunicorn main:app"
echo "======================================"
