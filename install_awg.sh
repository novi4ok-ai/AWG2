#!/bin/bash
# Скрипт автоматической установки и настройки клиента AmneziaWG (AWG2)

# --- Функции форматирования вывода ---
function print_status() {
    echo -e "\n[\e[32mСТАТУС\e[0m] $1"
}

function print_error() {
    echo -e "\n[\e[31mОШИБКА\e[0m] $1"
}

# --- Раздел справки ---
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Использование: sudo $0 [параметры]"
    echo ""
    echo "Параметры:"
    echo "  -h, --help    Показать эту справку"
    echo "  -c, --clean   Остановить туннель, удалить все установленные правила, цепочки и конфигурацию"
    echo ""
    echo "Описание:"
    echo "  Скрипт проверяет зависимости, устанавливает PPA Amnezia,"
    echo "  собирает модуль ядра amneziawg-dkms, запрашивает конфигурацию,"
    echo "  очищает ее от лишних параметров и настраивает автозапуск через systemd."
    exit 0
fi

# --- Проверка прав root ---
if [ "$EUID" -ne 0 ]; then
    print_error "Скрипт должен быть запущен с правами root. Используй: sudo $0"
    exit 1
fi

# --- Параметр очистки правил и конфигураций ---
if [[ "$1" == "-c" || "$1" == "--clean" ]]; then
    print_status "Удаление установленных правил, цепочек и конфигурации AWG..."
    systemctl stop awg-quick@awg0 2>/dev/null
    systemctl disable awg-quick@awg0 2>/dev/null
    awg-quick down awg0 2>/dev/null
    rm -f /etc/amnezia/amneziawg/awg0.conf
    print_status "Очистка успешно завершена."
    exit 0
fi

# --- Проверка ОС (только для Ubuntu) ---
if ! grep -qi "ubuntu" /etc/os-release; then
    print_error "Этот скрипт предназначен только для Ubuntu."
    exit 1
fi

# --- Установка зависимостей ---
print_status "Обновление списка пакетов и установка базовых зависимостей..."
apt-get update
if ! apt-get install -y software-properties-common linux-headers-$(uname -r) build-essential curl; then
    print_error "Не удалось установить базовые зависимости."
    exit 1
fi

# --- Добавление репозитория и установка AmneziaWG ---
print_status "Добавление PPA репозитория Amnezia (ppa:amnezia/ppa)..."
if ! add-apt-repository ppa:amnezia/ppa -y; then
    print_error "Ошибка при добавлении репозитория."
    exit 1
fi

print_status "Установка пакета amneziawg (DKMS-модуль и инструменты)..."
apt-get update
if ! apt-get install -y amneziawg; then
    print_error "Ошибка установки пакета amneziawg."
    exit 1
fi

# --- Подготовка директорий и конфигурации ---
CONF_DIR="/etc/amnezia/amneziawg"
CONF_FILE="$CONF_DIR/awg0.conf"

print_status "Подготовка структуры директорий..."
mkdir -p "$CONF_DIR"

print_status "Настройка конфигурации туннеля."
echo "============================================================"
echo "Скопируй содержимое твоего файла конфигурации (.conf)."
echo "Вставь его сюда, затем нажми Enter, и после этого Ctrl+D."
echo "============================================================"

# Читаем ввод пользователя до EOF (Ctrl+D) и пишем в файл
cat > "$CONF_FILE"

# Проверка, не пустой ли файл
if [ ! -s "$CONF_FILE" ]; then
    print_error "Конфигурация не введена (файл пуст). Установка прервана."
    exit 1
fi

print_status "Очистка конфигурации от известных артефактов (удаление строк I2=)..."
sed -i '/^I2=/d' "$CONF_FILE"

# Безопасность файла с приватным ключом
chmod 600 "$CONF_FILE"

# --- Настройка Systemd ---
print_status "Настройка автозапуска (systemd) и поднятие туннеля..."

# Отключаем ручной запуск, если он вдруг висит
awg-quick down awg0 2>/dev/null

systemctl enable awg-quick@awg0
if systemctl restart awg-quick@awg0; then
    sleep 2
    if systemctl is-active --quiet awg-quick@awg0; then
        print_status "Туннель awg0 успешно поднят и добавлен в автозагрузку!"
        echo -n "Текущий внешний IP-адрес: "
        curl -s ifconfig.me
        echo ""
    else
        print_error "Служба запущена, но туннель не активен. Проверь статус: systemctl status awg-quick@awg0"
    fi
else
    print_error "Не удалось запустить службу systemd для awg-quick."
    exit 1
fi

print_status "Установка завершена."
