#!/bin/bash

# Основные цвета
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
PURPLE='\033[35m'
MAGENTA='\033[35m'
LIGHT_PURPLE='\033[95m'
CYAN='\033[36m'
GRAY='\033[90m'
BLACK='\033[30m'
WHITE='\033[37m'
LIGHT_WHITE='\033[97m'

# Форматы текста
BOLD='\033[1m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
BLINK='\033[5m'          # Мигающий текст (поддерживается не всеми терминалами)
REVERSE='\033[7m'        # Инверсия цветов фона и текста
HIDDEN='\033[8m'         # Скрытый текст
STRIKETHROUGH='\033[9m'  # Зачеркнутый текст (поддерживается не всеми терминалами)
DOUBLE_UNDERLINE='\033[21m' # Двойное подчеркивание (поддерживается не всеми терминалами)

# Сброс стилей
RESET_BOLD='\033[22m'    # Сброс жирного/тусклого текста
RESET_ITALIC='\033[23m'  # Сброс курсива
RESET_UNDERLINE='\033[24m' # Сброс подчеркивания
RESET_BLINK='\033[25m'   # Сброс мигания
RESET_REVERSE='\033[27m' # Сброс инверсии
RESET_HIDDEN='\033[28m'  # Сброс скрытого текста
RESET_STRIKETHROUGH='\033[29m' # Сброс зачеркивания

# True Color (24-bit) примеры
# Формат: \033[38;2;R;G;Bm для текста, \033[48;2;R;G;Bm для фона
TRUE_RED='\033[38;2;255;0;0m'
TRUE_GREEN='\033[38;2;0;255;0m'
TRUE_BLUE='\033[38;2;0;0;255m'
TRUE_YELLOW='\033[38;2;255;255;0m'
TRUE_PURPLE='\033[38;2;128;0;128m'
TRUE_ORANGE='\033[38;2;255;165;0m'
TRUE_PINK='\033[38;2;255;192;203m'

# Фоновые True Color примеры
BG_TRUE_RED='\033[48;2;255;0;0m'
BG_TRUE_GREEN='\033[48;2;0;255;0m'
BG_TRUE_BLUE='\033[48;2;0;0;255m'
BG_TRUE_YELLOW='\033[48;2;255;255;0m'

# Яркие версии стандартных цветов
LIGHT_RED='\033[91m'
LIGHT_GREEN='\033[92m'
LIGHT_YELLOW='\033[93m'
LIGHT_BLUE='\033[94m'
LIGHT_CYAN='\033[96m'

# Дополнительные цвета из 256-цветной палитры
PINK='\033[38;5;213m'
LIME='\033[38;5;119m'
TEAL='\033[38;5;23m'
GOLD='\033[38;5;220m'
BROWN='\033[38;5;130m'
TURQUOISE='\033[38;5;45m'
ORANGE='\033[38;5;208m'

# Популярные комбинации
BOLD_RED='\033[1;31m'
ITALIC_BLUE='\033[3;34m'
UNDERLINE_GREEN='\033[4;32m'
BOLD_UNDERLINE='\033[1;4m'
BOLD_RED_BG_YELLOW='\033[1;31;43m'

# Фоновые цвета
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_MAGENTA='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'
BG_BLACK='\033[40m'

# Фоновые яркие цвета
BG_LIGHT_BLACK='\033[100m'
BG_LIGHT_RED='\033[101m'
BG_LIGHT_GREEN='\033[102m'
BG_LIGHT_YELLOW='\033[103m'
BG_LIGHT_BLUE='\033[104m'
BG_LIGHT_MAGENTA='\033[105m'
BG_LIGHT_CYAN='\033[106m'
BG_LIGHT_WHITE='\033[107m'

# Сброс всех настроек (должна быть в конце любого цветного вывода)
NC='\033[0m' 
