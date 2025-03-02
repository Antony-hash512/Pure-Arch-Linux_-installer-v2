#!/bin/bash
#export PYTHONUNBUFFERED=1  # Отключает буферизацию для Python

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

# Функция для получения списка компонентов
get_component_list() {
    local component_type=$1
    local component_list
    
    # Получаем список компонентов данного типа
    component_list="$(python3 get_data_from_components_xml.py list_${component_type} 2>&1)"
    
    # Проверяем, получен ли список компонентов
    if [ -z "$component_list" ]; then
        echo "ОШИБКА: Не удалось получить список компонентов типа '${component_type}'" >&2
        echo "Проверьте правильность имени типа компонента и наличие файла components.xml" >&2
        return 1
    fi
    
    # Возвращаем список компонентов
    echo "$component_list"
}

# Функция для запроса ID компонента у пользователя
request_component_id() {
    local component_type=$1
    local prompt_text=$2
    local component_list=$3
    local component_id
    
    # Запрашиваем у пользователя ID компонента
    read -p "${prompt_text}:" component_id
    
    # Проверяем, существует ли компонент с указанным ID
    while true; do 
        if echo "$component_list" | grep -qw "$component_id"; then
            echo "Выбран компонент '$component_id' типа '${component_type}'"
            break
        else
            echo "Компонент с ID '$component_id' типа '${component_type}' не найден"
            echo "Введите другой ID компонента или совершите выход при помощи ctrl+C"
            
            # Выводим список компонентов снова
            echo "Доступные компоненты типа '${component_type}':"
            for id in $component_list; do
                description="$(python3 get_data_from_components_xml.py ${component_type} $id get_description)"
                echo "  - $id: $description"
            done
            
            read -p "${prompt_text}:" component_id
        fi
    done
    
    # Возвращаем выбранный ID
    echo "$component_id"
}

# Выбор драйверов
DRIVERS_LIST=$(get_component_list "driverspack")
echo "Доступные компоненты типа 'driverspack':"
for id in $DRIVERS_LIST; do
    description="$(python3 get_data_from_components_xml.py driverspack $id get_description)"
    echo "  - $id: $description"
done
DRIVERS_ID=$(request_component_id "driverspack" "Введите ID пакета драйверов для установки" "$DRIVERS_LIST")
echo "Выбран пакет драйверов: $DRIVERS_ID"

# Выбор программного обеспечения
SOFTPACK_LIST=$(get_component_list "softpack")
echo "Доступные компоненты типа 'softpack':"
for id in $SOFTPACK_LIST; do
    description="$(python3 get_data_from_components_xml.py softpack $id get_description)"
    echo "  - $id: $description"
done
SOFTPACK_ID=$(request_component_id "softpack" "Введите ID набора программного обеспечения для установки" "$SOFTPACK_LIST")
echo "Выбран набор ПО: $SOFTPACK_ID"

# Выбор места установки
INSTALL_LOCATION_LIST=$(get_component_list "install_location")
echo "Доступные компоненты типа 'install_location':"
for id in $INSTALL_LOCATION_LIST; do
    description="$(python3 get_data_from_components_xml.py install_location $id get_description)"
    echo "  - $id: $description"
done
INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID места установки" "$INSTALL_LOCATION_LIST")
echo "Выбрано место установки: $INSTALL_LOCATION_ID"

# Выбор настроек
SETTINGS_LIST=$(get_component_list "settings")
echo "Доступные компоненты типа 'settings':"
for id in $SETTINGS_LIST; do
    description="$(python3 get_data_from_components_xml.py settings $id get_description)"
    echo "  - $id: $description"
done
SETTINGS_ID=$(request_component_id "settings" "Введите ID настроек системы" "$SETTINGS_LIST")
echo "Выбраны настройки: $SETTINGS_ID"