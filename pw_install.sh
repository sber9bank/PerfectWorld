#!/bin/bash

# Цвета
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'
BOX='\033[1;44m'

# Спиннер (анимация ожидания)
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    return $?
}

# Коробка с заголовком
print_box() {
    echo -e "\n${BOX} $1 ${RESET}\n"
}

# Сообщения
print_info() {
    echo -e "${BLUE}➤ $1${RESET}"
}

print_success() {
    echo -e "${GREEN}[✔] $1${RESET}"
}

print_error() {
    echo -e "${RED}[✖] $1${RESET}"
}

# Прогресс-бар
progress_bar() {
    local i=0
    local total=20
    while [ $i -le $total ]; do
        sleep 0.05
        printf "["
        for ((j=0; j<=i; j++)); do printf "■"; done
        for ((j=i; j<total; j++)); do printf " "; done
        printf "] %d%%\r" $(( i * 100 / total ))
        ((i++))
    done
    echo ""
}

# Запуск команды с анимацией и сообщением результата
run_cmd() {
    eval "$1" &> /dev/null &
    spinner
    if [ $? -eq 0 ]; then
        print_success "$2"
    else
        print_error "$2"
    fi
}

# Проверка запуска от root
if [ "$(id -u)" -ne 0 ]; then
    print_error "Этот скрипт должен быть запущен от root"
    exit 1
fi

print_box "🛠 НАЧАЛО УСТАНОВКИ"

progress_bar

# Шаг 1: Архитектура и обновление
print_box "🏗 Добавление архитектуры i386 и обновление системы"
run_cmd "dpkg --add-architecture i386" "Архитектура i386 добавлена"
run_cmd "apt update && apt -y upgrade" "Система обновлена"

# Шаг 2: Основные пакеты
print_box "📦 Установка основных пакетов"
run_cmd "apt -y install mc screen htop openjdk-11-jre mono-complete exim4 p7zip* libpcap-dev curl wget ipset net-tools tzdata ntpdate mariadb-server mariadb-client" "Основные пакеты установлены"

# Шаг 3: Зависимости для разработки
print_box "🔧 Установка зависимостей для разработки"
run_cmd "apt -y install make gcc g++ libssl-dev:i386 libssl-dev libcrypto++-dev libpcre3 libpcre3-dev libpcre3:i386 libpcre3-dev:i386 libtesseract-dev libx11-dev:i386 libx11-dev gcc-multilib libc6-dev:i386 build-essential g++-multilib libtemplate-plugin-xml-perl libxml2-dev libxml2-dev:i386 libxml2:i386 libstdc++6:i386 libmariadb-dev-compat:i386 libmariadb-dev:i386" "Зависимости для разработки установлены"

# Шаг 4: Библиотеки для БД
print_box "📚 Установка библиотек БД"
run_cmd "apt -y install libdb++-dev:i386 libdb-dev:i386 libdb5.3:i386 libdb5.3++:i386 libdb5.3++-dev:i386 libdb5.3-dbg:i386 libdb5.3-dev:i386" "Библиотеки БД (i386) установлены"
run_cmd "apt -y install libdb++-dev libdb-dev libdb5.3 libdb5.3++ libdb5.3++-dev libdb5.3-dbg libdb5.3-dev" "Библиотеки БД (64-bit) установлены"

# Шаг 5: Прочие зависимости
print_box "➕ Дополнительные зависимости"
run_cmd "apt -y install libmysqlcppconn-dev libjsoncpp-dev libmariadb-dev-compat curl libcurl4:i386 libcurl4-gnutls-dev" "Дополнительные зависимости установлены"

# Шаг 6: Apache и PHP
print_box "🌐 Установка Apache и PHP"
run_cmd "apt -y install apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip" "Apache и PHP установлены"
run_cmd "systemctl restart apache2" "Apache перезапущен"

# Шаг 7: Adminer
print_box "📁 Установка Adminer"
run_cmd "wget -O /var/www/html/adminer.php https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php" "Adminer скачан"
run_cmd "chown www-data:www-data /var/www/html/adminer.php" "Права владельца установлены"
run_cmd "chmod 755 /var/www/html/adminer.php" "Права доступа применены"

# Шаг 8: Настройка MySQL/MariaDB
print_box "🛡 Проверка конфигурации MySQL/MariaDB"

# Проверка: есть ли пароль у root
mysqladmin -u root status &> /dev/null
if [ $? -eq 0 ]; then
    print_info "У MySQL/MariaDB root всё ещё нет пароля. Запрашиваем пароль для настройки."
    read -p "Введите пароль для пользователя MySQL root (пусто = root): " MYSQL_ROOT_PASSWORD
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}
    run_cmd "mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';\"" "Пароль root установлен"
else
    print_info "У MySQL/MariaDB root уже настроен пароль. Пропускаем установку пароля."
    read -s -p "Введите текущий пароль root для продолжения (нужно только для настройки Adminer): " MYSQL_ROOT_PASSWORD
    echo ""
fi

run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"DELETE FROM mysql.user WHERE User='';\"" "Анонимные пользователи удалены"
run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"DROP DATABASE IF EXISTS test;\"" "Тестовая база удалена"
run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"FLUSH PRIVILEGES;\"" "Права обновлены (FLUSH PRIVILEGES)"

# Шаг 9: Конфиг Adminer
print_box "📝 Создание конфигурации Adminer"
cat > /var/www/html/adminer-config.php <<EOF
<?php
function adminer_object() {
    include_once "./plugins/plugin.php";
    class AdminerCustomization extends AdminerPlugin {
        function name() { return 'Adminer - MySQL Manager'; }
        function credentials() { return array('localhost', 'root', '${MYSQL_ROOT_PASSWORD}'); }
        function login(\$login, \$password) {
            return (\$login == 'root' && \$password == '${MYSQL_ROOT_PASSWORD}');
        }
    }
    return new AdminerCustomization();
}
EOF
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
run_cmd "a2enmod rewrite && systemctl restart apache2" "Apache настроен (rewrite включён)"

# Финал
print_box "✅ ГОТОВО"
echo -e "${CYAN}Доступ: http://your-ip/adminer.php"
echo -e "Пользователь: root"
echo -e "Пароль: ${MYSQL_ROOT_PASSWORD}${RESET}"
