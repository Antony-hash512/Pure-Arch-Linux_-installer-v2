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

# Тесты будут работать только на реальной системе
echo -e "${YELLOW}Тестирование функции check_uuid_exists на реальной системе${NC}"

# Функция для запуска теста
run_test() {
    local test_name="$1"
    local input="$2"
    
    # Вызываем тестируемую функцию
    device_path=$(check_uuid_exists "$input" 2>/dev/null)
    exit_code=$?
    
    # Определяем результат на основе кода выхода
    if [[ $exit_code -eq 0 ]]; then
        result="true"
        echo -e "${GREEN}УСПЕХ${NC}: $test_name"
        echo "  UUID: '$input'"
        echo "  Устройство: '$device_path'"
    elif [[ $exit_code -eq 1 ]]; then
        result="false"
        echo -e "${YELLOW}ИНФОРМАЦИЯ${NC}: $test_name"
        echo "  UUID: '$input'"
        echo "  Результат: Раздел не найден"
    else
        result="error"
        echo -e "${RED}ОШИБКА${NC}: $test_name"
        echo "  UUID: '$input'"
        echo "  Результат: Неверный UUID или другая ошибка"
    fi
}

# Тесты для проверки существования разделов по UUID
echo -e "${YELLOW}Тестирование функции проверки существования разделов по UUID:${NC}"

# Список UUID для тестирования
echo -e "${YELLOW}Тестируем следующие UUID:${NC}"
echo "Существующие UUID:"
echo "  - 19d66900-a87a-4784-94b3-18b9916f7997"
echo "  - b4494b1e-fc58-4c74-8e4d-3be22304658e"
echo "Несуществующий UUID:"
echo "  - xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Тесты с UUID
# Тесты с существующими UUID
run_test "Проверка существующего UUID 1" "19d66900-a87a-4784-94b3-18b9916f7997"
run_test "Проверка существующего UUID 2" "b4494b1e-fc58-4c74-8e4d-3be22304658e"

# Тест с несуществующим UUID
run_test "Проверка несуществующего UUID" "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Тест с пустым UUID
run_test "Проверка пустого UUID" ""

echo -e "\n${YELLOW}Все тесты выполнены.${NC}"

# Примечание: Для работы тестов необходимо реализовать функцию check_uuid_exists
# в файле include/main_functions.sh 