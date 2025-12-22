# Ansible Infrastructure Deployment

Этот проект содержит Ansible конфигурацию для автоматического развертывания инфраструктуры на двух виртуальных машинах (VM1 и VM2).

## Структура проекта

```
.
├── ansible.cfg                 # Конфигурация Ansible
├── inventory.yml              # Статический inventory с VM1 и VM2
├── site.yml                   # Главный playbook для полного развертывания
├── deploy.yml                 # Playbook для обновления приложения
├── group_vars/
│   └── all/
│       ├── vars.yml          # Основные переменные
│       └── vault.yml         # Зашифрованные пароли (ansible-vault)
└── roles/
    ├── common/               # Базовая настройка системы
    │   ├── tasks/
    │   ├── handlers/
    │   └── defaults/
    ├── database/             # Установка и настройка PostgreSQL
    │   ├── tasks/
    │   ├── handlers/
    │   ├── templates/
    │   └── defaults/
    ├── application/          # Деплой Flask приложения
    │   ├── tasks/
    │   ├── handlers/
    │   ├── templates/
    │   └── defaults/
    └── webserver/           # Настройка Nginx
        ├── tasks/
        ├── handlers/
        ├── templates/
        └── defaults/
```

## Роли

### 1. common
- Обновление системы
- Создание пользователя devops
- Установка Docker
- Настройка firewall (UFW + iptables)

### 2. database
- Установка PostgreSQL 15 (через Docker)
- Создание базы данных и пользователей
- Настройка доступа через pg_hba.conf
- Использование зашифрованных паролей из ansible-vault

### 3. application
- Создание пользователя приложения
- Создание Python virtual environment
- Установка Flask приложения
- Настройка systemd сервиса для автозапуска
- Установка зависимостей из requirements.txt

### 4. webserver
- Установка и настройка Nginx
- Настройка reverse proxy для Flask приложения
- Настройка логирования и security headers
- Оптимизация производительности (gzip, keepalive)

## Использование

### Предварительные требования

1. Ansible установлен на control node
2. SSH доступ к VM1 и VM2 с ключом
3. Python 3 установлен на целевых хостах
4. Sudo права на целевых хостах

### Настройка

1. **Обновите inventory.yml** с вашими IP адресами и SSH ключами:
```yaml
vm1:
  ansible_host: YOUR_VM1_IP
  ansible_ssh_private_key_file: /path/to/your/key
vm2:
  ansible_host: YOUR_VM2_IP
  ansible_ssh_private_key_file: /path/to/your/key
```

2. **Зашифруйте пароли с помощью ansible-vault**:
```bash
# Создайте файл с паролем для vault
echo "your-vault-password" > .vault_pass

# Зашифруйте файл с паролями
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file .vault_pass

# Или отредактируйте зашифрованный файл
ansible-vault edit group_vars/all/vault.yml --vault-password-file .vault_pass
```

3. **Добавьте .vault_pass в .gitignore**:
```bash
echo ".vault_pass" >> .gitignore
```

### Запуск

#### Полное развертывание всей инфраструктуры:
```bash
# С файлом пароля
ansible-playbook site.yml --vault-password-file .vault_pass

# Или с интерактивным вводом пароля
ansible-playbook site.yml --ask-vault-pass

# Проверка без выполнения (dry-run)
ansible-playbook site.yml --check --vault-password-file .vault_pass
```

#### Обновление только приложения:
```bash
ansible-playbook deploy.yml --vault-password-file .vault_pass
```

#### Запуск конкретной роли:
```bash
# Только database роль на VM2
ansible-playbook site.yml --tags database --limit vm2 --vault-password-file .vault_pass

# Только webserver роль на VM1
ansible-playbook site.yml --tags webserver --limit vm1 --vault-password-file .vault_pass
```

### Проверка

После развертывания проверьте работоспособность:

```bash
# Проверка Flask приложения напрямую
curl http://VM1_IP:5000/

# Проверка через Nginx
curl http://VM1_IP/

# Проверка health endpoint
curl http://VM1_IP/health

# Проверка PostgreSQL
ssh user@VM2_IP
docker exec -it postgres psql -U postgres -d appdb
```

## Idempotency

Все роли написаны с соблюдением принципа idempotency - повторный запуск playbook не вызывает изменений, если система уже находится в целевом состоянии.

## Handlers

Каждая роль использует handlers для перезапуска сервисов только при необходимости:
- **common**: restart docker, reload ufw
- **database**: restart postgresql
- **application**: reload systemd, restart application
- **webserver**: restart nginx, reload nginx

## Templates (Jinja2)

Используются шаблоны для конфигурационных файлов:
- PostgreSQL: `postgresql.conf.j2`, `pg_hba.conf.j2`
- Application: `app.py.j2`, `requirements.txt.j2`, `flask-app.service.j2`
- Nginx: `nginx.conf.j2`, `site.conf.j2`

## Безопасность

- Пароли хранятся в зашифрованном виде (ansible-vault)
- Firewall настроен на обоих хостах
- Nginx использует security headers
- Приложение запускается от непривилегированного пользователя
- SSH ключевая аутентификация

## Troubleshooting

### Проблема с подключением
```bash
# Проверка доступности хостов
ansible all -m ping --vault-password-file .vault_pass

# Проверка inventory
ansible-inventory --list -y
```

### Проблема с vault
```bash
# Просмотр зашифрованного файла
ansible-vault view group_vars/all/vault.yml --vault-password-file .vault_pass

# Расшифровка файла
ansible-vault decrypt group_vars/all/vault.yml --vault-password-file .vault_pass
```

### Логи сервисов
```bash
# Логи Flask приложения
sudo journalctl -u flask-app -f

# Логи Nginx
sudo tail -f /var/log/nginx/flask-app-error.log
sudo tail -f /var/log/nginx/flask-app-access.log

# Логи PostgreSQL
docker logs postgres -f
```

## Дополнительные команды

```bash
# Список всех тасков в playbook
ansible-playbook site.yml --list-tasks

# Список всех хостов
ansible-playbook site.yml --list-hosts

# Подробный вывод
ansible-playbook site.yml -vvv --vault-password-file .vault_pass

# Запуск с определенными тегами
ansible-playbook site.yml --tags "common,webserver" --vault-password-file .vault_pass
```
