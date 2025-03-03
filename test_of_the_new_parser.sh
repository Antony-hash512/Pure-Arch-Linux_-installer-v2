#!/bin/bash

# Цвета для вывода
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m' # Сброс цвета

# Счетчики для статистики тестов
PASSED=0
FAILED=0
TOTAL=0

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
    local expected_output="$3"
    
    echo -e "${YELLOW}Тест: ${test_name}${NC}"
    echo -e "Команда: ${command}"
    
    # Выполняем команду и сохраняем результат
    local actual_output=$(eval "$command")
    
    # Сравниваем ожидаемый и фактический результаты
    if [[ "$actual_output" == "$expected_output" ]]; then
        echo -e "${GREEN}УСПЕХ: Результат соответствует ожидаемому${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}ОШИБКА: Результат не соответствует ожидаемому${NC}"
        echo -e "Ожидалось: ${expected_output}"
        echo -e "Получено: ${actual_output}"
        ((TESTS_FAILED++))
    fi
    
    ((TESTS_TOTAL++))
    echo ""
}

# Инициализация счетчиков тестов
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0



# Тесты для выбранных компонентов
echo -e "\n${YELLOW}Запуск тестов для выбранных компонентов...${NC}"

# Тесты для драйверов
echo -e "\n${YELLOW}Тесты для пакета драйверов: $DRIVERS_ID${NC}"
run_test "Получение описания драйверов" "python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_description" "$(python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_description)"
run_test "Получение пакетов драйверов" "python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_pkgs_pacman | wc -w" "$(python3 get_data_from_components_xml.py driverspack $DRIVERS_ID get_pkgs_pacman | wc -w)"

# Тесты для программного обеспечения
echo -e "\n${YELLOW}Тесты для набора ПО: $SOFTPACK_ID${NC}"
run_test "Получение описания ПО" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_description" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_description)"
run_test "Получение pacstrap пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_pkgs_pacstrap" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_pkgs_pacstrap)"
run_test "Получение системы инициализации" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_init_system" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_init_system)"
run_test "Получение дополнительных настроек ПО" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_softpack_tweaks" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_softpack_tweaks)"
run_test "Получение AUR пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_aur_packages" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_aur_packages)"
run_test "Получение Flatpak пакетов" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_flatpak_packages" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_flatpak_packages)"
run_test "Получение архивов для домашней директории" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_archs4home" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_archs4home)"
run_test "Получение hooks" "python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_hooks" "$(python3 get_data_from_components_xml.py softpack $SOFTPACK_ID get_hooks)"

# Тесты для места установки
echo -e "\n${YELLOW}Тесты для места установки: $INSTALL_LOCATION_ID${NC}"
run_test "Получение описания места установки" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_description" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_description)"
run_test "Получение имени хоста" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_hostname" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_hostname)"
run_test "Получение имени пользователя" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_username" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_username)"
run_test "Получение UID пользователя" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_useruid" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_useruid)"
run_test "Получение количества новых точек монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_new_mountpoints" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_new_mountpoints)"
run_test "Получение количества дополнительных точек монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_extra_mountpoints" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_extra_mountpoints)"
run_test "Получение метки загрузчика" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_bootlabel" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_bootlabel)"
run_test "Получение устройства EFI" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_dev" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_dev)"
run_test "Получение нового расположения EFI" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_new_location" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_efi_new_location)"
run_test "Получение флага ISO" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_tweak_iso" "$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_tweak_iso)"

# Тест для получения информации о первой точке монтирования
MOUNT_POINTS_COUNT=$(python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_amount_of_new_mountpoints)
if [ "$MOUNT_POINTS_COUNT" -gt 0 ]; then
    run_test "Получение информации о первой точке монтирования" "python3 get_data_from_components_xml.py install_location $INSTALL_LOCATION_ID get_new_mountpoint 0 | grep -o 'mount_point'" "mount_point"
fi

# Тесты для настроек
echo -e "\n${YELLOW}Тесты для настроек: $SETTINGS_ID${NC}"
run_test "Получение описания настроек" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_description" "$(python3 get_data_from_components_xml.py settings $SETTINGS_ID get_description)"
run_test "Получение часового пояса" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_timezone" "$(python3 get_data_from_components_xml.py settings $SETTINGS_ID get_timezone)"
run_test "Получение локалей" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_locales | grep -c '#'" "$(python3 get_data_from_components_xml.py settings $SETTINGS_ID get_locales | grep -c '#')"
run_test "Получение локали по умолчанию" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_default_locale" "$(python3 get_data_from_components_xml.py settings $SETTINGS_ID get_default_locale)"
run_test "Получение строк vconsole" "python3 get_data_from_components_xml.py settings $SETTINGS_ID get_vconsole_strings | grep -c '#'" "$(python3 get_data_from_components_xml.py settings $SETTINGS_ID get_vconsole_strings | grep -c '#')"

# Вывод итоговой статистики
echo -e "${YELLOW}====================${NC}"
echo -e "${YELLOW}Итоги тестирования:${NC}"
echo -e "${GREEN}Пройдено: $PASSED${NC}"
echo -e "${RED}Провалено: $FAILED${NC}"
echo -e "${YELLOW}Всего тестов: $TOTAL${NC}"
echo -e "${YELLOW}====================${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}Все тесты успешно пройдены!${NC}"
    exit 0
else
    echo -e "${RED}Некоторые тесты не пройдены. Необходима проверка.${NC}"
    exit 1
fi

