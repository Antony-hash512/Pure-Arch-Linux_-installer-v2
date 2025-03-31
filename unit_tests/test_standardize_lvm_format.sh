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
    
    result=$(standardize_lvm_format "$input")
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}УСПЕХ${NC}: $test_name"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
        echo "  Входные данные: '$input'"
    else
        echo -e "${RED}ОШИБКА${NC}: $test_name"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
        echo "  Входные данные: '$input'"
    fi
}

# Тесты для различных форматов LVM устройств
echo "Тестирование стандартизации форматов LVM устройств:"
run_test "Формат mapper" "/dev/mapper/vgname-lvname" "/dev/vgname/lvname"
run_test "Формат vg/lv" "/dev/vgname/lvname" "/dev/vgname/lvname"
run_test "Формат mapper с дефисами" "/dev/mapper/vg--name-lv--name" "/dev/vg-name/lv-name"
run_test "Формат mapper с подчеркиваниями" "/dev/mapper/vg_name-lv_name" "/dev/vg_name/lv_name"

# Тесты для нестандартных имен
echo -e "\nТестирование нестандартных имен LVM устройств:"
run_test "Формат mapper с точками" "/dev/mapper/vg.name-lv.name" "/dev/vg.name/lv.name"
run_test "Формат mapper с плюсами" "/dev/mapper/vg+name-lv+name" "/dev/vg+name/lv+name"
run_test "Формат mapper с комбинированными символами" "/dev/mapper/vg_name.test-lv--name+test" "/dev/vg_name.test/lv-name+test"

echo -e "\nВсе тесты выполнены." 