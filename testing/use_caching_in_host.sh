#!/bin/bash

if ! pacman -Qi pacserve &>/dev/null; then
    echo "для кеширования уже скачанных пакетов необходимо установить пакет pacserve из aur"
    read -p "Нажмите Enter для продолжения"
    exit 0
fi

# Проверяем и запускаем pacserve, если он не запущен
if ! systemctl is-active --quiet pacserve; then
    echo "потребуется ввести пароль от root для запуска pacserve и pacserve-ports.service"
    sudo systemctl start pacserve
else
    echo "Сервис pacserve уже запущен"
fi

# Проверяем и запускаем pacserve-ports.service, если он не запущен
if ! systemctl is-active --quiet pacserve-ports.service; then
    sudo systemctl start pacserve-ports.service
else
    echo "Сервис pacserve-ports.service уже запущен"
fi