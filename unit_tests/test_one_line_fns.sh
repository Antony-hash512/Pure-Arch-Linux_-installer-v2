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
    local function_name="$4"
    
    if [[ "$function_name" == "one_line" ]]; then
        result=$(one_line "$input")
    elif [[ "$function_name" == "one_line_with_commas" ]]; then
        result=$(one_line_with_commas "$input")
    fi
    
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

# Тестовые данные с переносами строк
multiline_text="первая строка
вторая строка
третья строка"

# Тесты для функции one_line
echo "Тестирование функции one_line:"
run_test "Многострочный текст" "$multiline_text" "первая строка вторая строка третья строка" "one_line"
run_test "Пустой ввод" "" "" "one_line"
run_test "Однострочный текст" "одна строка" "одна строка" "one_line"

# Тесты для функции one_line_with_commas
echo -e "\nТестирование функции one_line_with_commas:"
run_test "Многострочный текст с запятыми" "$multiline_text" "первая строка,вторая строка,третья строка" "one_line_with_commas"
run_test "Пустой ввод для commas" "" "" "one_line_with_commas"
run_test "Однострочный текст для commas" "одна строка" "одна строка" "one_line_with_commas"

echo -e "\nВсе тесты выполнены." 