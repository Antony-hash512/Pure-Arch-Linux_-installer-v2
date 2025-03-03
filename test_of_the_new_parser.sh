#!/bin/bash

# Цвета для вывода
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
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

# Функция для запуска тестов и вывода результатов
run_test() {
    local test_name="$1"
    local command="$2"
    
    echo -e "${YELLOW}Тест: ${test_name}${NC}"
    echo -e "Команда: ${command}"
    
    # Выполняем команду и выводим результат
    local actual_output=$(eval "$command")
    echo -e "Результат: ${actual_output}"
    
    echo ""
}

# Тесты для выбранных компонентов
echo -e "\n${YELLOW}Запуск тестов для выбранных компонентов...${NC}"

# Тесты для драйверов
echo -e "\n${YELLOW}Тесты для пакета драйверов: $DRIVERS_ID${NC}"
run_test "Получение описания драйверов" "python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_description"
run_test "Получение пакетов драйверов" "python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_pkgs_pacman"

# Тесты для программного обеспечения
echo -e "\n${YELLOW}Тесты для набора ПО: $SOFTPACK_ID${NC}"
run_test "Получение описания ПО" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_description"
run_test "Получение pacstrap пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_pkgs_pacstrap"
run_test "Получение системы инициализации" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_init_system"
run_test "Получение дополнительных настроек ПО" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_softpack_tweaks"
run_test "Получение пакетов для установки" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_pkgs_pacman"
run_test "Получение AUR пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_aur_packages"
run_test "Получение Flatpak пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_flatpak_packages"
run_test "Получение архивов для домашней директории" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_archs4home"

# Тесты для места установки
echo -e "\n${YELLOW}Тесты для места установки: $INSTALL_LOCATION_ID${NC}"
run_test "Получение описания места установки" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_description"
run_test "Получение имени хоста" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_hostname"
run_test "Получение имени пользователя" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_username"
run_test "Получение UID пользователя" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_useruid"
run_test "Получение количества новых точек монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_new_mountpoints"
run_test "Получение количества дополнительных точек монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_extra_mountpoints"
run_test "Получение метки загрузчика" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_bootlabel"
run_test "Получение устройства EFI" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_dev"
run_test "Получение нового расположения EFI" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_new_location"
run_test "Получение флага ISO" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_tweak_iso"
run_test "Получение hooks" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_hooks"


# Тест для получения информации о первой точке монтирования
MOUNT_POINTS_COUNT=$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_new_mountpoints)
if [ "$MOUNT_POINTS_COUNT" -gt 0 ]; then
    run_test "Получение информации о первой точке монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_new_mountpoint 0"
fi

# Тесты для настроек
echo -e "\n${YELLOW}Тесты для настроек: $SETTINGS_ID${NC}"
run_test "Получение описания настроек" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_description"
run_test "Получение часового пояса" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_timezone"
run_test "Получение локалей" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_locales"
run_test "Получение локали по умолчанию" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_default_locale"
run_test "Получение строк vconsole" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_vconsole_strings"

read -p "Нажмите Enter для завершения..."

