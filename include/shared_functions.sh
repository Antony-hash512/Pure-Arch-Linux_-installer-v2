#!/bin/bash

parse_xml() {
    local component=$1
    local command=$2
    local optional_args=("${@:3}")
    case $component in
        "driverspack")
            python3 $XML_PARSER driverspack $DRIVERSPACK_ID $command
            ;;
        "softpack")
            python3 $XML_PARSER softpack $SOFTPACK_ID $command
            ;;
        "install_location")
            python3 $XML_PARSER install_location $INSTALL_LOCATION_ID $command "${optional_args[@]}"
            ;;
        "settings")
            python3 $XML_PARSER settings $SETTINGS_ID $command
            ;;
    esac

}

sync_time() {
    # Проверяем наличие systemd и используем соответствующий метод синхронизации времени
    if command -v timedatectl &> /dev/null; then
        # Система с systemd
        timedatectl set-ntp true
    elif command -v ntpd &> /dev/null; then
        # Система с ntpd
        ntpd -s
    elif command -v chronyd &> /dev/null; then
        # Система с chronyd
        chronyd
    elif command -v ntpdate &> /dev/null; then
        # Используем ntpdate для разовой синхронизации
        ntpdate -s pool.ntp.org
    else
        echo -e "${YELLOW}Предупреждение: не найден сервис синхронизации времени. Время может быть неточным.${NC}"
    fi
}
