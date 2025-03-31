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
    local type="$4"

    if [[ "$type" == "vg" ]]; then
        result=$(get_vg_name_from_fulldevname "$input")
    elif [[ "$type" == "lv" ]]; then
        result=$(get_lv_name_from_fulldevname "$input")
    fi
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}УСПЕХ${NC}: $test_name"
        echo "  Входные данные: '$input'"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
    else
        echo -e "${RED}ОШИБКА${NC}: $test_name"
        echo "  Входные данные: '$input'"
        echo "  Ожидалось: '$expected'"
        echo "  Получено:  '$result'"
    fi
}

#при задании через mapper в basename должен быть один и только один одиночный дефис из идущих подряд
#если там встречаются ещё дефисы, в остальных местах их количество подряд должно быть кратно двум

# Тесты для стандартных форматов LVM устройств
echo "Тестирование извлечения имен групп томов (VG):"
run_test "Формат mapper - VG" "/dev/mapper/vgname-lvname" "vgname" "vg"
run_test "Формат vg/lv - VG" "/dev/vgname/lvname" "vgname" "vg"
run_test "Формат mapper с дефисами - VG" "/dev/mapper/vg--name-lv--name" "vg-name" "vg"
run_test "Формат vg/lv с дефисами - VG" "/dev/vg-name/lv-name" "vg-name" "vg"

echo -e "\nТестирование извлечения имен логических томов (LV):"
run_test "Формат mapper - LV" "/dev/mapper/vgname-lvname" "lvname" "lv"
run_test "Формат vg/lv - LV" "/dev/vgname/lvname" "lvname" "lv"
run_test "Формат mapper с дефисами - LV" "/dev/mapper/vg--name-lv--name" "lv-name" "lv"
run_test "Формат vg/lv с дефисами - LV" "/dev/vg-name/lv-name" "lv-name" "lv"

# Тесты для нестандартных имен
echo -e "\nТестирование извлечения имен из нестандартных форматов (VG):"
run_test "Формат mapper с подчеркиваниями - VG" "/dev/mapper/vg_name-lv_name" "vg_name" "vg"
run_test "Формат vg/lv с подчеркиваниями - VG" "/dev/vg_name/lv_name" "vg_name" "vg"
run_test "Формат mapper с точками - VG" "/dev/mapper/vg.name-lv.name" "vg.name" "vg"
run_test "Формат vg/lv с точками - VG" "/dev/vg.name/lv.name" "vg.name" "vg"
run_test "Формат mapper с плюсами - VG" "/dev/mapper/vg+name-lv+name" "vg+name" "vg"
run_test "Формат vg/lv с плюсами - VG" "/dev/vg+name/lv+name" "vg+name" "vg"

echo -e "\nТестирование извлечения имен из нестандартных форматов (LV):"
run_test "Формат mapper с подчеркиваниями - LV" "/dev/mapper/vg_name-lv_name" "lv_name" "lv"
run_test "Формат vg/lv с подчеркиваниями - LV" "/dev/vg_name/lv_name" "lv_name" "lv"
run_test "Формат mapper с точками - LV" "/dev/mapper/vg.name-lv.name" "lv.name" "lv"
run_test "Формат vg/lv с точками - LV" "/dev/vg.name/lv.name" "lv.name" "lv"
run_test "Формат mapper с плюсами - LV" "/dev/mapper/vg+name-lv+name" "lv+name" "lv"
run_test "Формат vg/lv с плюсами - LV" "/dev/vg+name/lv+name" "lv+name" "lv"

# Тесты для комбинированных специальных символов
echo -e "\nТестирование извлечения имен из комбинированных форматов (VG):"
run_test "Формат mapper с комбинированными символами - VG" "/dev/mapper/vg_name.test-lv--name+test" "vg_name.test" "vg"
run_test "Формат vg/lv с комбинированными символами - VG" "/dev/vg_name.test/lv-name+test" "vg_name.test" "vg"

echo -e "\nТестирование извлечения имен из комбинированных форматов (LV):"
run_test "Формат mapper с комбинированными символами - LV" "/dev/mapper/vg_name.test-lv--name+test" "lv-name+test" "lv"
run_test "Формат vg/lv с комбинированными символами - LV" "/dev/vg_name.test/lv-name+test" "lv-name+test" "lv"

# Тесты для сложных случаев
echo -e "\nТестирование сложных случаев (VG):"
run_test "Множественные дефисы в VG и LV - VG" "/dev/mapper/vg--with--many--dashes-lv--with--many--dashes" "vg-with-many-dashes" "vg"
run_test "Множественные дефисы через путь VG - VG" "/dev/vg-with-many-dashes/lv-with-many-dashes" "vg-with-many-dashes" "vg"

echo -e "\nТестирование сложных случаев (LV):"
run_test "Множественные дефисы в VG и LV - LV" "/dev/mapper/vg--with--many--dashes-lv--with--many--dashes" "lv-with-many-dashes" "lv"
run_test "Множественные дефисы через путь VG - LV" "/dev/vg-with-many-dashes/lv-with-many-dashes" "lv-with-many-dashes" "lv"

echo -e "\nВсе тесты выполнены." 
