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

# Флаг для работы с реальной системой
USE_REAL_SYSTEM=false

# Проверяем аргументы командной строки
for arg in "$@"; do
    if [[ "$arg" == "--real-sys" ]]; then
        USE_REAL_SYSTEM=true
        echo -e "${YELLOW}Используем реальную систему для проверки групп томов${NC}"
        
        # Проверяем, запущен ли скрипт с правами root
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}ОШИБКА: Для использования флага --real-sys необходимы права root!${NC}"
            echo -e "${YELLOW}Пожалуйста, запустите скрипт с использованием sudo:${NC}"
            echo -e "${YELLOW}sudo $0 --real-sys${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Тесты запущены с правами root. LVM команды должны работать корректно.${NC}"
        break
    fi
done

# Создаем фиктивные данные для тестирования
# Список существующих групп томов для имитации
EXISTING_VG_NAMES=(
    "mainvg"
    "bkpvg"
)

# Мокаем команду vgs для тестирования
# Перед запуском функции check_vg_exists определим временную функцию safe_vgs
# которая будет возвращать 0 (успех) только для имен из списка EXISTING_VG_NAMES
# функци переопределена для для имитации поведения реальной системы. Это позволяет тестировать функцию check_vg_exists с предсказуемыми результатами, независимо от реального состояния системы.



safe_vgs_original=$( declare -f safe_vgs )
override_safe_vgs() {
    local vg_name=""
    
    # Проверяем, есть ли аргументы
    if [[ $# -gt 0 ]]; then
        # Извлекаем имя группы из аргументов
        # В зависимости от того, как именно передается имя группы
        for arg in "$@"; do
            if [[ "$arg" == "/dev/"* ]]; then
                # Если аргумент в виде /dev/vgname/lvname или /dev/mapper/vgname-lvname
                vg_name=$(get_vg_name_from_fulldevname "$arg")
                break
            elif [[ "$arg" != "-"* && "$arg" != "--"* ]]; then
                # Если это просто имя группы без флагов
                vg_name="$arg"
                break
            fi
        done
    fi
    
    # Если имя группы не извлечено, возвращаем ошибку
    if [[ -z "$vg_name" ]]; then
        return 1
    fi
    
    # Проверяем, есть ли такая группа в списке существующих
    for existing_vg in "${EXISTING_VG_NAMES[@]}"; do
        if [[ "$existing_vg" == "$vg_name" ]]; then
            return 0 # Группа существует
        fi
    done
    
    return 1 # Группа не существует
}

# Функция для запуска теста
run_test() {
    local test_name="$1"
    local input="$2"
    local expected_mock="$3"
    local expected_real="$4"
    
    # Если ожидаемый результат для реальной системы не указан, используем ожидаемый результат для имитации
    if [[ -z "$expected_real" ]]; then
        expected_real="$expected_mock"
    fi

    # Определяем ожидаемый результат в зависимости от режима работы
    local expected
    if [[ "$USE_REAL_SYSTEM" == true ]]; then
        expected="$expected_real"
    else
        expected="$expected_mock"
    fi
    
    # Переопределяем функцию safe_vgs для тестирования, только если не используем реальную систему
    if [[ "$USE_REAL_SYSTEM" == false ]]; then
        unset -f safe_vgs
        safe_vgs() {
            override_safe_vgs "$@"
        }
    fi
    
    # Вызываем тестируемую функцию
    if check_vg_exists "$input"; then
        result="true"
    else
        result="false"
    fi
    
    # Восстанавливаем оригинальную функцию safe_vgs, только если она была переопределена
    if [[ "$USE_REAL_SYSTEM" == false ]]; then
        unset -f safe_vgs
        eval "$safe_vgs_original"
    fi
    
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

# Выводим информацию о режиме работы
if [[ "$USE_REAL_SYSTEM" == true ]]; then
    echo -e "${YELLOW}Тестирование в режиме РЕАЛЬНОЙ СИСТЕМЫ${NC}"
else
    echo -e "${YELLOW}Тестирование в режиме ИМИТАЦИИ${NC}"
    echo -e "${YELLOW}Считаются существующими группы томов: ${EXISTING_VG_NAMES[*]}${NC}"
fi

# Тесты для проверки существования групп томов
echo -e "${YELLOW}Тестирование функции проверки существования групп томов LVM:${NC}"

# Тесты с именами групп
# Теперь у каждого теста может быть два ожидаемых результата: 
# для режима имитации (3-й параметр) и для реальной системы (4-й параметр)
run_test "Группа томов mainvg" "mainvg" "true" "true"
run_test "Группа томов bkpvg" "bkpvg" "true" "true"
run_test "Несуществующая группа томов" "nonexistent" "false" "false"

# Тесты с полными путями устройств
run_test "Путь к устройству в mainvg" "/dev/mainvg/root" "true" "true"
run_test "Путь к устройству в bkpvg" "/dev/bkpvg/backup" "true" "true"
run_test "Путь к устройству в несуществующей группе" "/dev/fakevg/root" "false" "false"
run_test "Путь mapper к устройству в mainvg" "/dev/mapper/mainvg-root" "true" "true"
run_test "Путь mapper к устройству в bkpvg" "/dev/mapper/bkpvg-backup" "true" "true"
run_test "Путь mapper к устройству в несуществующей группе" "/dev/mapper/fakevg-root" "false" "false"

echo -e "\n${YELLOW}Все тесты выполнены.${NC}"

# Примечание: Для работы тестов необходимо реализовать функцию check_vg_exists
# в файле include/main_functions.sh 