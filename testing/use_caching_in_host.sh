#!/bin/bash

if ! pacman -Qi pacserve &>/dev/null; then
    echo "для кеширования уже скачанных пакетов необходимо установить пакет pacserve из aur"
    read -p "Нажмите Enter для продолжения"
    exit 0
fi

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo "СБОЙ: Этот скрипт должен быть запущен от имени суперпользователя (root)" >&2
    exit 1
fi


cat /etc/pacserve/pacserve.service.conf
echo 'должно быть так: PACSERVE_ARGS="--multicast --avahi --trust-pacserve-peers"'
echo '1. обновить автоматически'
echo '2. обновить вручную'
echo '3. оставить как есть'
read -p "Выберите вариант: " choice

if [[ "$choice" == "1" ]]; then
    echo 'PACSERVE_ARGS="--multicast --avahi --trust-pacserve-peers"' > /etc/pacserve/pacserve.service.conf
elif [[ "$choice" == "2" ]]; then
    read -p "Введите текстовый редактор [по умолчанию: nano]: " editor
    editor=${editor:-nano}          # если ничего не ввели – возьмём nano
    "$editor" /etc/pacserve/pacserve.service.conf
else
    echo "Сервис pacserve не будет обновлен"
fi

# Проверяем и запускаем pacserve, если он не запущен
if ! systemctl is-active --quiet pacserve; then
    systemctl start pacserve

else
    echo "Сервис pacserve уже запущен"
fi

# Проверяем и запускаем pacserve-ports.service, если он не запущен
if ! systemctl is-active --quiet pacserve-ports.service; then
    systemctl start pacserve-ports.service
else
    echo "Сервис pacserve-ports.service уже запущен"
fi

echo "Для подключения к кешу пакетов из хоста на qemu запустите скрипт INSTALL.sh с флагом --cache-qemu-pkgs"