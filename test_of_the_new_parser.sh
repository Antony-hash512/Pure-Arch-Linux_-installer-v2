#!/bin/bash
: <<'COMMENT'
ALL_DRIVERS_PACKS="$(python3 get_data_from_components_xml.py list_driverspacks)"
ALL_SOFT_PACKS="$(python3 get_data_from_components_xml.py list_softpacks)"
ALL_INSTALL_LOCATIONS="$(python3 get_data_from_components_xml.py list_install_locations)"
ALL_SETTINGS_VARIANTS="$(python3 get_data_from_components_xml.py list_settings_variants)"

echo "В файле components.xml найдены следующие драйверные паки:"
for drv in $ALL_DRIVERS_PACKS; do
    description=$(python3 get_data_from_components_xml.py driverspack "$drv" get_description)
    echo "  $drv - $description"
done

echo -e "\nВ файле components.xml найдены следующие программные паки:"
for soft in $ALL_SOFT_PACKS; do
    description=$(python3 get_data_from_components_xml.py softpack "$soft" get_description)
    echo "  $soft - $description" 
done
COMMENT

# Определение переменных для цвета
RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m' # Сброс цвета


# Функция для запроса ID компонента у пользователя
request_component_id() {
    local component_type=$1
    local prompt_text=$2
    local component_list=$(python3 get_data_from_components_xml.py list_${component_type})
    local component_id

    echo "Доступные компоненты типа '${component_type}':" > /dev/tty
    for id in $component_list; do
        description="$(python3 get_data_from_components_xml.py ${component_type} $id get_description)"
        echo "  - $id: $description" > /dev/tty
    done
    
    # Запрашиваем у пользователя ID компонента
    read -p "${prompt_text}:" component_id
    
    # Проверяем, существует ли компонент с указанным ID
    while true; do 
        if echo "$component_list" | grep -qw "$component_id"; then
            echo -e "${GREEN}Выбран компонент '$component_id' типа '${component_type}'${NC}" > /dev/tty
            break
        else
            echo -e "${RED}Компонент с ID '$component_id' типа '${component_type}' не найден${NC}" >&2
            echo -e "${RED}Введите другой ID компонента или совершите выход при помощи ctrl+C${NC}" > /dev/tty
            
            # Выводим список компонентов снова
            echo "Доступные компоненты типа '${component_type}':" > /dev/tty
            for id in $component_list; do
                description="$(python3 get_data_from_components_xml.py ${component_type} $id get_description)"
                echo "  - $id: $description" > /dev/tty
            done
            
            read -p "${prompt_text}:" component_id
        fi
    done
    
    # Возвращаем выбранный ID
    echo "$component_id"
}

# Выбор драйверов
DRIVERS_ID=$(request_component_id "driverspack" "Введите ID пакета драйверов для установки")
echo -e "${GREEN}Выбран пакет драйверов: $DRIVERS_ID${NC}"

# Выбор программного обеспечения
SOFTPACK_ID=$(request_component_id "softpack" "Введите ID набора программного обеспечения для установки")
echo -e "${GREEN}Выбран набор ПО: $SOFTPACK_ID${NC}"

# Выбор места установки
INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID места установки")
echo -e "${GREEN}Выбрано место установки: $INSTALL_LOCATION_ID${NC}"

# Выбор настроек
SETTINGS_ID=$(request_component_id "settings" "Введите ID настроек системы")
echo -e "${GREEN}Выбраны настройки: $SETTINGS_ID${NC}"