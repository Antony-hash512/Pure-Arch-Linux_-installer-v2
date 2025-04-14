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
        echo -e "${YELLOW}Используем реальную систему для проверки UUID разделов${NC}"
        
        # Проверяем, запущен ли скрипт с правами root
        if [[ $EUID -ne 0 ]]; then
            echo -e "${RED}ОШИБКА: Для использования флага --real-sys необходимы права root!${NC}"
            echo -e "${YELLOW}Пожалуйста, запустите скрипт с использованием sudo:${NC}"
            echo -e "${YELLOW}sudo $0 --real-sys${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Тесты запущены с правами root. Команды должны работать корректно.${NC}"
        break
    fi
done

# Создаем фиктивные данные для тестирования
# Список существующих UUID для имитации (заполните своими значениями)
EXISTING_UUIDS=(
    "19d66900-a87a-4784-94b3-18b9916f7997" # Замените на реальные UUID
    "b4494b1e-fc58-4c74-8e4d-3be22304658e" # Замените на реальные UUID
)

# Ассоциативный массив для связывания UUID с путями устройств
declare -A UUID_TO_DEVICE
UUID_TO_DEVICE["xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"]="/dev/sdX1" # Замените на реальные пути
UUID_TO_DEVICE["yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"]="/dev/sdY1" # Замените на реальные пути

# Мокаем команду blkid для тестирования
# Сохраняем оригинальную функцию, если она определена
if command -v blkid &>/dev/null; then
    blkid_original="$(command -v blkid)"
fi

# Переопределяем команду blkid для тестирования
override_blkid() {
    local input_uuid=""
    
    # Проверяем аргументы
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -U)
                input_uuid="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Если UUID не задан, возвращаем ошибку
    if [[ -z "$input_uuid" ]]; then
        return 1
    fi
    
    # Проверяем, существует ли устройство с таким UUID
    for uuid in "${EXISTING_UUIDS[@]}"; do
        if [[ "$uuid" == "$input_uuid" ]]; then
            echo "${UUID_TO_DEVICE[$uuid]}"
            return 0
        fi
    done
    
    return 1
}

# Функция для запуска теста
run_test() {
    local test_name="$1"
    local input="$2"
    local expected_mock="$3"
    local expected_real="$4"
    local expected_device_mock="$5"
    local expected_device_real="$6"
    
    # Если ожидаемый результат для реальной системы не указан, используем ожидаемый результат для имитации
    if [[ -z "$expected_real" ]]; then
        expected_real="$expected_mock"
    fi
    
    if [[ -z "$expected_device_real" ]]; then
        expected_device_real="$expected_device_mock"
    fi

    # Определяем ожидаемый результат в зависимости от режима работы
    local expected
    local expected_device
    if [[ "$USE_REAL_SYSTEM" == true ]]; then
        expected="$expected_real"
        expected_device="$expected_device_real"
    else
        expected="$expected_mock"
        expected_device="$expected_device_mock"
    fi
    
    # Переопределяем команду blkid для тестирования, только если не используем реальную систему
    if [[ "$USE_REAL_SYSTEM" == false ]]; then
        function blkid() {
            override_blkid "$@"
        }
    fi
    
    # Вызываем тестируемую функцию
    device_path=$(check_uuid_exists "$input" 2>/dev/null)
    exit_code=$?
    
    # Определяем результат на основе кода выхода
    if [[ $exit_code -eq 0 ]]; then
        result="true"
    elif [[ $exit_code -eq 1 ]]; then
        result="false"
    else
        result="error"
    fi
    
    # Восстанавливаем оригинальную команду blkid, если она была переопределена
    if [[ "$USE_REAL_SYSTEM" == false ]]; then
        unset -f blkid
    fi
    
    # Проверяем результат
    local test_passed=true
    
    if [[ "$result" != "$expected" ]]; then
        test_passed=false
    fi
    
    if [[ "$result" == "true" && "$device_path" != "$expected_device" ]]; then
        test_passed=false
    fi
    
    if [[ "$test_passed" == true ]]; then
        echo -e "${GREEN}УСПЕХ${NC}: $test_name"
        echo "  Входные данные: '$input'"
        echo "  Ожидалось: '$expected' (код возврата)"
        echo "  Получено:  '$result' (код возврата)"
        if [[ "$result" == "true" ]]; then
            echo "  Ожидаемый путь: '$expected_device'"
            echo "  Полученный путь: '$device_path'"
        fi
    else
        echo -e "${RED}ОШИБКА${NC}: $test_name"
        echo "  Входные данные: '$input'"
        echo "  Ожидалось: '$expected' (код возврата)"
        echo "  Получено:  '$result' (код возврата)"
        if [[ "$result" == "true" || "$expected" == "true" ]]; then
            echo "  Ожидаемый путь: '$expected_device'"
            echo "  Полученный путь: '$device_path'"
        fi
    fi
}

# Выводим информацию о режиме работы
if [[ "$USE_REAL_SYSTEM" == true ]]; then
    echo -e "${YELLOW}Тестирование в режиме РЕАЛЬНОЙ СИСТЕМЫ${NC}"
else
    echo -e "${YELLOW}Тестирование в режиме ИМИТАЦИИ${NC}"
    echo -e "${YELLOW}Считаются существующими UUID: ${EXISTING_UUIDS[*]}${NC}"
fi

# Тесты для проверки существования разделов по UUID
echo -e "${YELLOW}Тестирование функции проверки существования разделов по UUID:${NC}"

# Тесты с UUID
# Теперь у каждого теста может быть до 6 параметров:
# 1 - Название теста
# 2 - UUID
# 3 - Ожидаемый результат для режима имитации (true/false)
# 4 - Ожидаемый результат для реальной системы (true/false)
# 5 - Ожидаемый путь для режима имитации
# 6 - Ожидаемый путь для реальной системы

# Тесты с существующими UUID
run_test "Существующий UUID 1" "b4494b1e-fc58-4c74-8e4d-3be22304658e" "true" "" "/dev/sdX1" ""
run_test "Существующий UUID 2" "19d66900-a87a-4784-94b3-18b9916f7997" "true" "" "/dev/sdY1" ""

# Тесты с несуществующими UUID
run_test "Несуществующий UUID" "19d66900-a87a-4784-94b3-18b9916f7998" "false" "" "" ""

# Тест с пустым UUID
run_test "Пустой UUID" "" "error" "" "" ""

echo -e "\n${YELLOW}Все тесты выполнены.${NC}"

# Примечание: Для работы тестов необходимо реализовать функцию check_uuid_exists
# в файле include/main_functions.sh 