#!/bin/bash

# Подключаем тестируемую функцию
# Получаем путь к директории текущего скрипта
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Подключаем файл с функциями из каталога include родительской директории
source "${SCRIPT_DIR}/../include/main_functions.sh"

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция для запуска теста
run_test() {
    local test_name="$1"
    local input="$2"
    local expected="$3"
    
    result=$(get_device_basename4lsblk "$input")
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}УСПЕХ${NC}: $test_name"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
    else
        echo -e "${RED}ОШИБКА${NC}: $test_name"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
    fi
}

# Тесты для стандартных устройств
echo "Тестирование стандартных устройств:"
run_test "Стандартное устройство sda" "/dev/sda" "sda"
run_test "Стандартный раздел sda1" "/dev/sda1" "sda1"
run_test "Устройство nvme" "/dev/nvme0n1" "nvme0n1"
run_test "Раздел nvme" "/dev/nvme0n1p42" "nvme0n1p42"

# Тесты для LVM устройств через mapper
echo -e "\nТестирование LVM устройств через mapper:"
run_test "Простое LVM через mapper" "/dev/mapper/vgname-lvname" "vgname-lvname"
run_test "LVM с подчеркиваниями" "/dev/mapper/vg_name-lv_name" "vg_name-lv_name"

# Тест для LUKS устройств
echo -e "\nТестирование LUKS устройств:"
run_test "LUKS устройство" "/dev/mapper/opened_luks_basename_838798_83" "opened_luks_basename_838798_83"

# Тесты для LVM устройств через vgpath
echo -e "\nТестирование LVM устройств через путь VG:"
run_test "Простое LVM через путь VG" "/dev/vgname/lvname" "vgname-lvname"
run_test "LVM с подчеркиваниями через путь VG" "/dev/vg_name/lv_name" "vg_name-lv_name"

# Тесты с дефисами в именах
echo -e "\nТестирование устройств с дефисами в именах:"
run_test "LVM с дефисами через mapper" "/dev/mapper/vg--name-lv--name" "vg--name-lv--name"
run_test "LVM с дефисами через путь VG" "/dev/vg-name/lv-name" "vg--name-lv--name"
run_test "LVM с несколькими дефисами через путь VG" "/dev/vg-with-many-dashes/lv-with-many-dashes" "vg--with--many--dashes-lv--with--many--dashes"
run_test "LVM с несколькими дефисами подряд через путь VG" "/dev/vg---name/lv--name" "vg------name-lv----name"

# Тесты с точками в именах
echo -e "\nТестирование устройств с точками в именах:"
run_test "LVM с точкой через mapper" "/dev/mapper/vg.name-lv.name" "vg.name-lv.name"
run_test "LVM с точкой через путь VG" "/dev/vg.name/lv.name" "vg.name-lv.name"

# Тесты с плюсами в именах
echo -e "\nТестирование устройств с плюсами в именах:"
run_test "LVM с плюсом через mapper" "/dev/mapper/vg+name-lv+name" "vg+name-lv+name"
run_test "LVM с плюсом через путь VG" "/dev/vg+name/lv+name" "vg+name-lv+name"

# Тест на неизвестный формат
echo -e "\nТестирование неизвестного формата:"
run_test "Неизвестный формат" "/invalid/path" ""

echo -e "\nВсе тесты выполнены." 