#!/bin/bash

# Подключаем тестируемую функцию
# Получаем путь к директории текущего скрипта
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Подключаем файл с функциями из каталога include родительской директории
source "${SCRIPT_DIR}/../include/main_functions.sh"

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Создаем фиктивные данные для тестирования
# Список существующих групп томов
EXISTING_VG_NAMES=(
    "mainvg"
    "bkpvg"
)

# Мокаем команду vgs для тестирования
# Перед запуском функции check_vg_exists определим временную функцию safe_vgs
# которая будет возвращать 0 (успех) только для имен из списка EXISTING_VG_NAMES
# функци переопределена для для имитации поведения реальной системы. Это позволяет тестировать функцию check_vg_exists с предсказуемыми результатами, независимо от реального состояния системы.

# нужно или привести список в соответствие с реальной системой или раскомментировать:

#safe_vgs_original=$( declare -f safe_vgs )
#override_safe_vgs() {
#    local vg_name=""
#    
#    # Проверяем, есть ли аргументы
#    if [[ $# -gt 0 ]]; then
#        # Извлекаем имя группы из аргументов
#        # В зависимости от того, как именно передается имя группы
#        for arg in "$@"; do
#            if [[ "$arg" == "/dev/"* ]]; then
#                # Если аргумент в виде /dev/vgname/lvname или /dev/mapper/vgname-lvname
#                vg_name=$(get_vg_name_from_fulldevname "$arg")
#                break
#            elif [[ "$arg" != "-"* && "$arg" != "--"* ]]; then
#                # Если это просто имя группы без флагов
#                vg_name="$arg"
#                break
#            fi
#        done
#    fi
#    
#    # Если имя группы не извлечено, возвращаем ошибку
#    if [[ -z "$vg_name" ]]; then
#        return 1
#    fi
#    
#    # Проверяем, есть ли такая группа в списке существующих
#    for existing_vg in "${EXISTING_VG_NAMES[@]}"; do
#        if [[ "$existing_vg" == "$vg_name" ]]; then
#            return 0 # Группа существует
#        fi
#    done
#    
#    return 1 # Группа не существует
#}
#
# Функция для запуска теста
run_test() {
    local test_name="$1"
    local input="$2"
    local expected="$3"
    
    # Переопределяем функцию safe_vgs для тестирования
    unset -f safe_vgs
    safe_vgs() {
        override_safe_vgs "$@"
    }
    
    # Вызываем тестируемую функцию
    if check_vg_exists "$input"; then
        result="true"
    else
        result="false"
    fi
    
    # Восстанавливаем оригинальную функцию safe_vgs
    unset -f safe_vgs
    eval "$safe_vgs_original"
    
    # Проверяем результат
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

# Тесты для проверки существования групп томов
echo -e "${YELLOW}Тестирование функции проверки существования групп томов LVM:${NC}"

# Тесты с именами групп
run_test "Существующая группа томов" "mainvg" "true"
run_test "Существующая группа томов" "bkpvg" "true"
run_test "Несуществующая группа томов" "nonexistent" "false"

# Тесты с полными путями устройств
run_test "Путь к устройству в существующей группе" "/dev/mainvg/root" "true"
run_test "Путь к устройству в существующей группе" "/dev/bkpvg/backup" "true"
run_test "Путь к устройству в несуществующей группе" "/dev/fakevg/root" "false"
run_test "Путь mapper к устройству в существующей группе" "/dev/mapper/mainvg-root" "true"
run_test "Путь mapper к устройству в существующей группе" "/dev/mapper/bkpvg-backup" "true"
run_test "Путь mapper к устройству в несуществующей группе" "/dev/mapper/fakevg-root" "false"

echo -e "\n${YELLOW}Все тесты выполнены.${NC}"

# Примечание: Для работы тестов необходимо реализовать функцию check_vg_exists
# в файле include/main_functions.sh 