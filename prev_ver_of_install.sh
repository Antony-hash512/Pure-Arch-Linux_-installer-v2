#!/bin/bash

# Это устаревший скрипт был использован для установки системы в прошлом
# Наработки из него в процессе переноса в новую версию скрипта

#=======================================================================================

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mERROR: This script must be run as root\033[0m" >&2
    exit 1
fi

echo "Bash version: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
echo ""
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    :
else
    echo "The required version of Bash is 4.3 or higher" >&2
    exit 1
fi


# Подключаем файл с переменными для цвета
source include/colors.sh

# Заранее вычисленные степени 1024
MB=1048576  # 1024^2
GB=1073741824  # 1024^3
TB=1099511627776  # 1024^4
PB=1125899906842624  # 1024^5
EB=1152921504606846976  # 1024^6

# Стоковые константы
AUTODIR="autocreated_scripts"
XML_FILE="components.xml"
XML_PARSER="get_data_from_components_xml.py"
CHROOT_SCRIPT="run_inside_chroot.sh"


echo "test тест"
echo "если этот текст можно прочитать, то можно продолжать без смены шрифта"
echo "Do you want to switch to a font with Cyrillic support? (Y/n)"
read -r USE_CYRILLIC_FONT
if [[ -z "$USE_CYRILLIC_FONT" || "$USE_CYRILLIC_FONT" =~ ^[Yy]$ ]]; then
    setfont cyr-sun16
    echo "test тест"
    echo "была использована команда setfont cyr-sun16"
    echo "if it doesn't work, you can use Ctrl+C to exit and to solve this problem by another way"
else
    echo "Остаемся на стандартном шрифте (if the cyrillic font doesn't work, you can use Ctrl+C to exit)"
fi
#далее считается что кириллица поддерживается (ведем диалог с пользователем на русском, английская версия будет реализована позже, пока что нет смысла)
echo "перед использованием скрипта также должен быть настроен доступ в интернет и выпонена необходимая минимальная разбивка разделов на диске"
read -p "Enter - продолжить; ctrl+C - прервать"


pacman -Sy
packages=("arch-install-scripts" "terminus-font" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr" "python" "bc")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)

#функция для перевода в байты
convert_to_bytes() {
    local size=$1
    
    # Проверяем формат: должны быть только цифры и одна буква на конце
    if ! [[ $size =~ ^[0-9]+[A-Za-z]?$ ]]; then
        echo "Ошибка: неверный формат '$size'. Должны быть только цифры и одна буква на конце." >&2
        exit 1
    fi
    
    local num=${size//[^0-9]/}  # Извлекаем число
    local unit=${size//[0-9]/}   # Извлекаем единицу измерения
    unit=${unit^^}  # Приводим к верхнему регистру
    #мегабайты в lvcreate используются по умолчанию но без буквы не используем для совместимости с другими утилитами типа dd

    case "$unit" in
        "E") echo $((num * EB)) ;;  # 1 ЭБ = 1024^6 B
        "P") echo $((num * PB)) ;;  # 1 ПБ = 1024^5 B
        "T") echo $((num * TB)) ;;  # 1 ТБ = 1024^4 B
        "G") echo $((num * GB)) ;;  # 1 ГБ = 1024^3 B
        "M") echo $((num * MB)) ;;  # 1 МБ = 1024^2 B
        "K") echo $((num * 1024)) ;;  # 1 КБ = 1024 B
        "B") echo "$num" ;;               # Байты
        *) echo "Ошибка: неизвестная единица '$unit' в записи '$size'" >&2; exit 1 ;;
    esac
}

ask_user_to_exit() {
    local question=$1
    #local error_message=$2
    echo "$question (y/n)"
    read -r exit_choice
    if [[ "$exit_choice" == "y" || "$exit_choice" == "Y" ]]; then
        exit 1
    fi
}

# Функция для запроса ID компонента у пользователя
request_component_id() {
    local component_type=$1
    local prompt_text=$2
    local component_list=$(python3 $XML_PARSER list_${component_type})
    local component_id

    echo "Доступные компоненты типа '${component_type}':" > /dev/tty
    for id in $component_list; do
        description="$(python3 $XML_PARSER ${component_type} $id get_description)"
        echo -e "  - ${GREEN}$id${NC}: $description" > /dev/tty
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
                description="$(python3 $XML_PARSER ${component_type} $id get_description)"
                echo -e "  - ${GREEN}$id${NC}: $description" > /dev/tty
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

parse_xml() {
    local component=$1
    local command=$2
    local optional_args=("${@:3}")
    case $component in
        "driverspack")
            python3 $XML_PARSER driverspack $DRIVERSPACK_ID $command
            ;;
        "softpack")
            python3 $XML_PARSER softpack $SOFTPACK_ID $command
            ;;
        "install_location")
            python3 $XML_PARSER install_location $INSTALL_LOCATION_ID $command "${optional_args[@]}"
            ;;
        "settings")
            python3 $XML_PARSER settings $SETTINGS_ID $command
            ;;
    esac

}

# откуда устанавливается система
if [[ $(parse_xml install_location get_tweak_iso) == "true" ]]; then
    INSTALL_FROM="iso"
else
    INSTALL_FROM="other_system"
fi

# Запрашиваем у пользователя, нужно ли создавать скрипт удаления
echo -e "Создать скрипт для удаления установленной системы в каталоге ${MAGENTA}${AUTODIR}${NC}? (Y/n)"
read -r CREATE_REMOVE_SCRIPT
if [[ -z "$CREATE_REMOVE_SCRIPT" || "$CREATE_REMOVE_SCRIPT" =~ ^[Yy]$ ]]; then
    DONT_CREATE_NEW_REMOVE_SCRIPT=false
else
    DONT_CREATE_NEW_REMOVE_SCRIPT=true
fi

# случаи для legacy будут добавлены потом

EFI_DEV="$(parse_xml install_location get_efi_dev)"
EFI_NEW_LOCATION="$(parse_xml install_location get_efi_new_location)"


: <<'COMMENT'
Сейчас это прописывается не здесь, а в components.xml
Примеры использования:
declare -A new_point0=(
    ["mount_point"]="/" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="pwd_in_none" 
    ["name"]="@arch_system_test42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
)

declare -A new_point1=(
    ["mount_point"]="/home" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="key_in_none" 
    ["name"]="@arch_openhome_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
    ["keyfile"]=/etc/home.key
)

* возможные значения type: format_ext4, new_subvol_in_btrfs, new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm
* также я думаю имеет смысл добавить: new_subvol_in_new_btrfs, new_subvol_in_new_btrfs_in_lvm, new_subvol_in_new_btrfs_in_new_lvm, new_ext4_in_new_lvm


* возможные значение crypt_mode: (для format_ext4, new_subvol_in_btrfs): none, file, pwd, (для new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm): none_in_none, none_in_file, none_in_pwd, file_in_none, pwd_in_none: (случаи двойного шифорования не рассматриваем из-за избыточности такого действия), file или pwd - какой метод расшифровки будет использован при загрузке системы файл с ключём или пароль?
* keyfile: путь к файлу ключа (где создать или откуда использовать), требуется только при использовании опции с file
* name: название(я) тома(oв) и/или раздела (для вложенной структуры нужно использовать разделение "_in_" например: @arch_system42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8)

для уже существующих разделов значения type немного отличаются:
in_main_gpt, subvol_in_btrfs, subvol_in_btrfs_in_lvm, volume_in_lvm

пример:
declare -A extra_point1=(
    ["mount_point"]="/ntfs/c" 
    ["type"]="in_main_gpt" 
    ["crypt_mode"]="none" 
    ["name"]="/dev/nvme0n1p2"
)

COMMENT

# Создаём ассоциативные массивы для каждой строки "двумерного" массива
# C именем new_point+число
# корневой каталог должен быть первым, а вложенные быть после родительских
# получаем количество точек монтирования
ALL_NEW_POINTS_COUNT="$(parse_xml install_location get_amount_of_new_mountpoints)"
ALL_EXTRA_POINTS_COUNT="$(parse_xml install_location get_amount_of_extra_mountpoints)"
# создаём массивы для новых точек монтирования
for ((i=0; i<ALL_NEW_POINTS_COUNT; i++)); do
    declare -A new_point$i="$(parse_xml install_location get_new_mountpoint $i)"
done
# создаём массивы для дополнительных точек монтирования
for ((i=0; i<ALL_EXTRA_POINTS_COUNT; i++)); do
    declare -A extra_point$i="$(parse_xml install_location get_extra_mountpoint $i)"
done



## дополнительные точки монтирования будут реализованы позже
#declare -A extra_point1=(
#    ["mount_point"]="/ntfs/c" 
#    ["type"]="in_main_gpt" 
#    ["crypt_mode"]="none" 
#    ["name"]="/dev/nvme0n1p2"
#)


#получаем список пакетов для pacstrap
SOFT_PACK1="$(parse_xml softpack get_pkgs_pacstrap)"

#===============конец настроек=============================================================

#Обновление времени
timedatectl set-ntp true


# Получаем путь к каталогу, где находится скрипт
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

# Показываем пользователю список записей EFI
echo -e "${YELLOW}Список записей EFI:${NC}"
efibootmgr

EFI_SYS_NAME="$(parse_xml install_location get_efi_bootlabel)"

# Проверяем уникальность имени и предлагаем варианты
while true; do
    if efibootmgr | grep -q "$EFI_SYS_NAME"; then
        echo -e "${RED}Загрузчик с именем ${MAGENTA}$EFI_SYS_NAME${RED} уже существует.${NC}"
        read -p "Хотите перезаписать существующий загрузчик? (type YES using Capital letters): " overwrite
        if [[ $overwrite =~ ^YES$ ]]; then
            echo -e "${GREEN}Будет выполнена перезапись существующего загрузчика.${NC}"
            break
        else
            read -p "Введите другое имя загрузчика в EFI-разделе: " EFI_SYS_NAME
        fi
    else
        echo -e "${GREEN}Имя загрузчика ${MAGENTA}$EFI_SYS_NAME${GREEN} уникально и будет использовано.${NC}"
        break
    fi
done

# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

ALL_EXTRA_POINTS=()
for var in $(compgen -A variable | grep -E '^extra_point[0-9]+$'); do
    ALL_EXTRA_POINTS+=("$var")
done

#выводим на экран список точек монтирования
#это отобразилось как mount_point0 и mount_point1 т.е. только названия без подробной информации
#нужно вывести подробную информацию о каждой точке монтирования
echo -e "${YELLOW}список точек монтирования:${NC}"
for item in "${ALL_NEW_POINTS[@]}"; do
    echo "$item"
done
if [[ "${#ALL_EXTRA_POINTS[@]}" -gt 0 ]]; then
    echo -e "${YELLOW}список дополнительных точек монтирования:${NC}"
    for item in "${ALL_EXTRA_POINTS[@]}"; do
        echo "$item"
    done
fi
echo -e "${YELLOW}список разделов до начала установки:${NC}"
lsblk -o NAME,FSTYPE,FSVER,SIZE,FSAVAIL,FSUSE%,RM,RO,MOUNTPOINTS
read -p "Enter - продолжить; ctrl+C - прервать"


if [[ "$DONT_CREATE_NEW_REMOVE_SCRIPT" == "false" ]]; then
    # Задаём массивы для последующей записи в дополнительно созданый скрипт для удаления системы
    LVM_VOLUMES=()
    declare -A BTRFS_SUBVOLUMES
    #определяем как там заданы массивы в одну строчку или нет
    lvm_single_line=''
    btrfs_single_line=''
     
    while IFS= read -r line; do
        if [[ "$line" =~ ^LVM_VOLUMES=\(.*\)$ ]]; then
            lvm_single_line='true'
        elif [[ "$line" =~ ^LVM_VOLUMES=\([^\)]*$ ]]; then
            lvm_single_line='false'
        elif [[ "$line" =~ ^BTRFS_SUBVOLUMES=\(.*\)$ ]]; then
            btrfs_single_line='true'
        elif [[ "$line" =~ ^BTRFS_SUBVOLUMES=\([^\)]*$ ]]; then
            btrfs_single_line='false'
        fi
    done < "$SCRIPT_DIR/REMOVE_INSTALED_SYSTEM.sh"
    
    if [[ -z "$lvm_single_line" || -z "$btrfs_single_line" ]]; then
        echo "Ошибка: не найдены LVM_VOLUMES или BTRFS_SUBVOLUMES в скрипте REMOVE_INSTALED_SYSTEM.sh" >&2
        exit 1
    fi    
fi

#ассоциативный массив для хранения точек монтирования корневых разделов всех btrfs
declare -A ALL_ROOT_BTRFS_MOUNTPOINTS

#####начало отладки
echo "ALL_NEW_POINTS: ${ALL_NEW_POINTS[@]}"
#вывод всех элементов массива
for item in "${ALL_NEW_POINTS[@]}"; do
    echo "$item"
    declare -n current_array="$item"
    for key in "${!current_array[@]}"; do
        echo "[$key]=${current_array[$key]}"
    done
done    

echo "ALL_EXTRA_POINTS: ${ALL_EXTRA_POINTS[@]}" 
#вывод всех элементов массива   
for item in "${ALL_EXTRA_POINTS[@]}"; do
    echo "$item"
done    

#####конец отладки



# Обходим массивы, используя их имена
i=0;
for row in "${ALL_NEW_POINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    if [[ "$i" -eq 0 && "${current_row["mount_point"]}" != "/" ]]; then
        echo "Ошибка: первой должна быть /" >&2
        exit 1
    fi
    ((i++))
    number=$(echo "$row" | grep -o '[0-9]\+')
    echo "$i. (Номер из после \"new_point\": $number)"
    
    
    echo "Точка монтирования: ${current_row["mount_point"]}"
    echo "Тип размещения: ${current_row["type"]}"
    echo "Опция Шифрования: ${current_row["crypt_mode"]}"
    echo "Имя (Имена) раздела/томов: ${current_row["name"]}"
    echo ""

    #создаём новый ассоциативный массив для посчёта того сколько требуется свободного места в каждой группе томов
    declare -A ALL_LVM_VOLUMES_REQUIRED_SPACE # для сличаев: new_ext4_in_lvm, new_subvol_in_new_btrfs_in_lvm, new_subvol_in_new_btrfs_in_new_lvm
    ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED=false


    # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    case "${current_row["type"]}" in
        "format_ext4")            
            ext4_path=${current_row["name"]}
            echo "Путь к разделу с ext4: $ext4_path"
            ;;
        "new_subvol_in_btrfs"|"new_subvol_in_btrfs_in_lvm")
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Путь к разделу Btrfs: $btrfs_device"
            #проверяем что этого раздела нет в массиве
            if [[ ! -v ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"] ]]; then
                #получаем имя точки монтирования используя время unix и случайное число
                CURRENT_BTRFS_MOUNTPOINT="/mnt/btrfs_root_$(date +%s)_$RANDOM"
                ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]="$CURRENT_BTRFS_MOUNTPOINT"
                #создаём каталог для точки монтирования
                mkdir -p "$CURRENT_BTRFS_MOUNTPOINT"
                #монтируем раздел
                mount "$btrfs_device" "$CURRENT_BTRFS_MOUNTPOINT"
            fi

            # выводим список сабволюмов
            btrfs_subvolumes_str=$(echo "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}"| xargs -I {} sudo btrfs subvolume list {})           
            #btrfs_subvolumes_str=$(sudo btrfs subvolume list "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}")
            echo "Список существующих подтомов в $btrfs_device:"
            echo "$btrfs_subvolumes_str"

            #проверяем, что нет такого сабтома
            if echo "$btrfs_subvolumes_str" | grep -w -q "$subvol_name"; then
                echo "Ошибка: Подтом с именем $subvol_name уже существует в $btrfs_device" >&2
                exit 1
            else
                echo "имя подтома $subvol_name уникально и будет использовано"
            fi
            echo -e "${YELLOW}Отладочная информация о разделе:${NC}"
            TEST1=$(sudo btrfs filesystem usage -h "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}")
            echo "$TEST1"
            read -p "Enter - продолжить; ctrl+C - прервать"

            #гарантированно доступное свободное место в разделе:
            BTRFS_FREE_SPACE_AVAILABLE_RAW_DATA=$(sudo btrfs filesystem usage -h "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}" | grep Free | grep min)

            # Извлекаем числовую часть (40.87)
            BTRFS_FREE_SPACE_AVAILABLE_NUMBER=$(echo "$BTRFS_FREE_SPACE_AVAILABLE_RAW_DATA" | sed -E 's/.*min: ([0-9]+(\.[0-9]+)?)\s*[A-Za-z]+.*/\1/')
            #получаем целое число (40)
            BTRFS_FREE_SPACE_AVAILABLE_NUMBER_INTEGER=$(echo "$BTRFS_FREE_SPACE_AVAILABLE_NUMBER" | sed -E 's/^([0-9]+)(\.[0-9]+)?$/\1/')
            # Извлекаем буквенную часть (GiB)
            BTRFS_FREE_SPACE_AVAILABLE_UNIT=$(echo "$BTRFS_FREE_SPACE_AVAILABLE_RAW_DATA" | sed -E 's/.*min: [0-9.]+\s*([A-Za-z]+).*/\1/')

            # Извлекаем первую букву единицы измерения (G)
            BTRFS_FREE_SPACE_AVAILABLE_UNIT_FIRST_LETTER=$(echo "$BTRFS_FREE_SPACE_AVAILABLE_UNIT" | cut -c1)

            echo "Гарантированно доступное свободное место: $BTRFS_FREE_SPACE_AVAILABLE_NUMBER $BTRFS_FREE_SPACE_AVAILABLE_UNIT"

            #если буквенная часть это B,K или M выходим с ошибкой
            if [[ "$BTRFS_FREE_SPACE_AVAILABLE_UNIT_FIRST_LETTER" == "B" || "$BTRFS_FREE_SPACE_AVAILABLE_UNIT_FIRST_LETTER" == "K" || "$BTRFS_FREE_SPACE_AVAILABLE_UNIT_FIRST_LETTER" == "M" ]]; then
                echo -e "${RED}Предупреждение: Рекомендуется проверить свободное место в разделе $btrfs_device: $BTRFS_FREE_SPACE_AVAILABLE_NUMBER $BTRFS_FREE_SPACE_AVAILABLE_UNIT (меньше 1 гигабайта !!! это всё равно что 0 !!!)${NC}" >&2
                ask_user_to_exit "Рекомендуется выйти, чтобы проверить свободное место"
            elif [[ "$BTRFS_FREE_SPACE_AVAILABLE_UNIT_FIRST_LETTER" == "G" ]]; then
                    if [[ "${current_row["mount_point"]}" == "/" ]]; then
                    BTRFS_FREE_SPACE_REQUIRED=40
                else
                    BTRFS_FREE_SPACE_REQUIRED=5
                fi
                if [[ "$BTRFS_FREE_SPACE_AVAILABLE_NUMBER_INTEGER" -lt "$BTRFS_FREE_SPACE_REQUIRED" ]]; then
                    echo -e "${RED}Предупреждение: Рекомендуется проверить свободное место в разделе $btrfs_device: $BTRFS_FREE_SPACE_AVAILABLE_NUMBER $BTRFS_FREE_SPACE_AVAILABLE_UNIT (меньше $BTRFS_FREE_SPACE_REQUIRED гигабайт)${NC}" >&2
                    ask_user_to_exit "Хотите выйти, чтобы проверить свободное место?"
                fi
            fi

           
            if [[ "$DONT_CREATE_NEW_REMOVE_SCRIPT" == "false" ]]; then
                if [[ -v BTRFS_SUBVOLUMES["$btrfs_device"] ]]; then
                    BTRFS_SUBVOLUMES["$btrfs_device"]+="$subvol_name"
                else
                    BTRFS_SUBVOLUMES["$btrfs_device"]="$subvol_name"
                fi
            fi
            ;;
        "new_ext4_in_lvm")
            ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED=true
            lv_name="${names[0]}"
            lv_basename=$(basename "$lv_name")  # Получаем только имя тома
            vg_name=$(echo "$lv_name" | awk -F/ '{print $3}')  # Получаем имя группы томов
            echo "Логический том LVM (ext4): $lv_name"
            #проверяем существует ли группа томов
            if ! lvdisplay "/dev/$vg_name" &> /dev/null; then
                echo "Ошибка: Группа томов с именем $vg_name не существует" >&2
                echo "Создайте её вручную или используйте другой вариант установки" >&2
                exit 1
            fi
            # Проверяем, существует ли уже логический том с именем $lv_name
            if lvdisplay "/dev/$vg_name/$lv_basename" &> /dev/null; then
                echo "Ошибка: Логический том с именем $lv_basename уже существует в группе томов $vg_name" >&2
                echo -e "В ${BOLD}$XML_FILE${NC} требуется прописать новое новое уникальное имя для нового ext4 тома внутри lvm" >&2
                exit 1
            else
                echo "имя для нового логического тома $lv_basename уникально и будет использовано"
            fi
            # проверяем есть ли поле в ассоциативном массиве ALL_LVM_VOLUMES_REQUIRED_SPACE с названием группы томов $vg_name
            if [[ ! -v ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"] ]]; then
                ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"]=0
            fi
            # получаем размер нового тома из переменной size ${current_row["size"]} в байтах (функция задана в начале скрипта)
            size_in_bytes=$(convert_to_bytes "${current_row["size"]}")

            # добавляем размер нового тома в ассоциативный массив
            ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"]=$((ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"] + size_in_bytes))
            
            # Добавляем lv_name в массив LVM_VOLUMES
            if [[ "$DONT_CREATE_NEW_REMOVE_SCRIPT" == "false" ]]; then
                LVM_VOLUMES+=("$lv_name")
            fi
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
done

#проверяем доступное свободное место в группах томов
if [[ "$ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED" == "true" ]]; then
    for vg_name in "${!ALL_LVM_VOLUMES_REQUIRED_SPACE[@]}"; do
        echo "Требуемый размер для группы томов $vg_name: ${ALL_LVM_VOLUMES_REQUIRED_SPACE[$vg_name]} байт ($(echo "${ALL_LVM_VOLUMES_REQUIRED_SPACE[$vg_name]} / $GB" | bc) гигов)"
        #проверяем доступное свободное место группе томов в байтах
        free_space=$(vgs /dev/$vg_name --rows --nosuffix --units b | grep VFree | awk '{print $2}')
        echo "Доступное свободное место в группе томов $vg_name: $free_space байт ($(echo "$free_space / $GB" | bc) гигов)"
        if [[ "$free_space" -lt "${ALL_LVM_VOLUMES_REQUIRED_SPACE[$vg_name]}" ]]; then
            echo "Ошибка: Доступное свободное место в группе томов $vg_name меньше требуемого" >&2
            echo "Увеличте свободное место. После чего перезапустите установку" >&2
            exit 1
        else
            echo "свободного в группе томов места достаточно"
        fi
    done
fi


printf "\n\n"
echo -e "Точки монтирования и опции шифрования должны быть настроены путём редактирования файла ${BOLD}$XML_FILE${NC}"
echo "Корневой каталог должен быть первым, а вложенные быть после родительских"
read -p "Enter - продолжить; ctrl+C - прервать"


#### начало создания скрипта удаления

if [[ "$DONT_CREATE_NEW_REMOVE_SCRIPT" == "false" ]]; then
    echo "Будет создана дополнительна копия скрипта удаления системы, настроенная на удаление данной установки"
    NEW_SCRIPT_4REMOVE="$SCRIPT_DIR/autocreated_scripts/REMOVE_INSTALED_SYSTEM_${INSTALL_LOCATION_ID}_$(date +%Y-%m-%d_%H-%M).sh"
    cp "$SCRIPT_DIR/REMOVE_INSTALED_SYSTEM.sh" "$NEW_SCRIPT_4REMOVE"

    # Создаём строки для LVM_VOLUMES и BTRFS_SUBVOLUMES
    lvm_volumes_str=""
    for volume in "${LVM_VOLUMES[@]}"; do
        lvm_volumes_str+="    \"$volume\"\n"
    done
    
    # Записываем содержимое BTRFS_SUBVOLUMES в переменную в формате ["ключ"]="значения"
    btrfs_subvolumes_str=""
    for key in "${!BTRFS_SUBVOLUMES[@]}"; do
        btrfs_subvolumes_str+="    [\"$key\"]=\"${BTRFS_SUBVOLUMES[$key]}\"\n"
    done
    
    # Переводим символы новой строки (\n) в литеральные символы, чтобы sed корректно обработал
    lvm_volumes_str=$(echo -e "$lvm_volumes_str")
    btrfs_subvolumes_str=$(echo -e "$btrfs_subvolumes_str")
    
    # Экранируем все слеши в переменных, чтобы корректно работать с sed
    lvm_volumes_str=$(echo "$lvm_volumes_str" | sed 's/\//\\\//g')
    btrfs_subvolumes_str=$(echo "$btrfs_subvolumes_str" | sed 's/\//\\\//g')
    
    # закоменчиваем старые значения
    case "$lvm_single_line" in
        'false')
            sed -i '/^LVM_VOLUMES=(/,/^)/ {/^LVM_VOLUMES=(/!{/^)/!s/^/# /}}' "$NEW_SCRIPT_4REMOVE"
            ;;
        'true')
            sed -i 's/^LVM_VOLUMES=(/LVM_VOLUMES=(#/' "$NEW_SCRIPT_4REMOVE"
            sed -i '/^LVM_VOLUMES=(#/a )' "$NEW_SCRIPT_4REMOVE"
            ;;
        *)
            echo "Ошибка: неизвестное значение для lvm_single_line" >&2
            exit 1
            ;;
    esac
    
    case "$btrfs_single_line" in
        'false')
            sed -i '/^BTRFS_SUBVOLUMES=(/,/^)/ {/^BTRFS_SUBVOLUMES=(/!{/^)/!s/^/# /}}' "$NEW_SCRIPT_4REMOVE"
            ;;
        'true')
            sed -i 's/^BTRFS_SUBVOLUMES=(/BTRFS_SUBVOLUMES=(#/' "$NEW_SCRIPT_4REMOVE"
            sed -i '/^BTRFS_SUBVOLUMES=(#/a )' "$NEW_SCRIPT_4REMOVE"
            ;;
        *)
            echo "Ошибка: неизвестное значение для btrfs_single_line" >&2
            exit 1
            ;;
    esac
    
    # Вставляем новые значения после строки ^LVM_VOLUMES=( 
    while IFS= read -r line; do
        sed -i "/^LVM_VOLUMES=(/a \\
    $line" "$NEW_SCRIPT_4REMOVE"
    done <<< "$lvm_volumes_str"
    
    # Вставляем новые значения после строки ^BTRFS_SUBVOLUMES=( 
    while IFS= read -r line; do
        sed -i "/^BTRFS_SUBVOLUMES=(/a \\
    $line" "$NEW_SCRIPT_4REMOVE"
    done <<< "$btrfs_subvolumes_str"
    
    
    # выполняем замену в копии файла REMOVE_INSTALED_SYSTEM.sh
    sed -i "s/EFI_NOTE_TO_DELETE=\"\"/EFI_NOTE_TO_DELETE=\"$EFI_SYS_NAME\"/" "$NEW_SCRIPT_4REMOVE"
fi
#### конец создания скрипта удаления 

###################################################################

#ВНИМАНИЕ! тут начинается непосредственно установка


#добавляем к имени каталога текущую дату и время для уникальности
INST_DIR="/mnt/system_installing_$(date +%Y-%m-%d_%H-%M)"

mkdir -p $INST_DIR 
#проверка, что этот каталог не смонтирован
if mount | grep -q $INST_DIR; then
    echo "Ошибка: каталог $INST_DIR уже смонтирован" >&2
    exit 1
fi



for row in "${ALL_NEW_POINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
     # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    mount_point=${current_row["mount_point"]}

    #в каждый кейс прописан подкейс с опциями шифрования
    #заполняем случаи none_in_none и none
    case "${current_row["type"]}" in
        "format_ext4")            
            ext4_path=${current_row["name"]}
            case "${current_row["crypt_mode"]}" in
                "none")
                    #форматируем раздел
                    mkfs.ext4 $ext4_path
                    #создаём каталог $INST_DIR$mount_point если он не существует
                    mkdir -p $INST_DIR$mount_point
                    #монтируем раздел
                    mount $ext4_path $INST_DIR$mount_point
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs")
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            case "${current_row["crypt_mode"]}" in
                "none")
                    #создаём подтом
                    btrfs subvolume create "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}/$subvol_name"
                    #создаём каталог $INST_DIR$mount_point если он не существует
                    mkdir -p $INST_DIR$mount_point
                    #монтируем подтом в каталог установки (внутри chroot'а)
                    mount -o subvol=$subvol_name $btrfs_device $INST_DIR$mount_point
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs_in_lvm")
            #этот случай польностью протестирован (в режиме none_in_none)
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже


            mkdir -p $INST_DIR$mount_point
            
            case "${current_row["crypt_mode"]}" in
                #сейчас будем работать над вариантами шифрования
                #т.к. скипт работает с уже созданными разделами lvm и btrfs, то предпологается что они уже зашифрованы
                #для создания новых зашифрованных разделов нужно будет использовать другие случаи
                "none_in_none")
                    #создаём подтом
                    btrfs subvolume create "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}/$subvol_name"
                    #создаём каталог $INST_DIR$mount_point если он не существует
                    mkdir -p $INST_DIR$mount_point
                    #монтируем подтом в каталог установки (внутри chroot'а)
                    mount -o subvol=$subvol_name $btrfs_device $INST_DIR$mount_point
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            
            ;;
        "new_ext4_in_lvm")
            lv_name="${names[0]}"
            lv_basename=$(basename "$lv_name")  # Получаем только имя тома
            vg_name=$(echo "$lv_name" | awk -F/ '{print $3}')  # Получаем имя группы томов
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    
                    #создаём том с указанным размером
                    size=${current_row["size"]}
                    lvcreate -L $size -n $lv_basename $vg_name
                    #форматируем том
                    mkfs.ext4 /dev/$vg_name/$lv_basename
                    #создаём каталог $INST_DIR$mount_point если он не существует
                    mkdir -p $INST_DIR$mount_point
                    #монтируем том
                    mount /dev/$vg_name/$lv_basename $INST_DIR$mount_point
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    #создаём том с указанным размером
                    size=${current_row["size"]}
                    lvcreate -L $size -n $lv_basename $vg_name
                    # Шифрование логических томов
                    cryptsetup luksFormat /dev/$vg_name/$lv_basename
                    # Открытие зашифрованных томов
                    cryptsetup open /dev/$vg_name/$lv_basename crypt_$lv_basename

                    #форматируем том
                    mkfs.ext4 /dev/mapper/crypt_$lv_basename
                    #создаём каталог $INST_DIR$mount_point если он не существует
                    mkdir -p $INST_DIR$mount_point
                    #монтируем том
                    mount /dev/mapper/crypt_$lv_basename $INST_DIR$mount_point
                    #создаём пустой массив CRYPT_VOLUMES если он не существует
                    if [[ ! -v CRYPT_VOLUMES[@] ]]; then
                        declare -a CRYPT_VOLUMES
                    fi
                    #добавляем lv_name в массив CRYPT_VOLUMES
                    CRYPT_VOLUMES+=("/dev/$vg_name/$lv_basename")
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_new_btrfs")
            case "${current_row["crypt_mode"]}" in
                "none")
                    :
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_new_btrfs_in_lvm")
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_new_btrfs_in_new_lvm")
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_ext4_in_new_lvm")
            case "${current_row["crypt_mode"]}" in
                "none")
                    :
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
    

done

#монтируем раздел EFI
mkdir -p $INST_DIR/$EFI_NEW_LOCATION
mount $EFI_DEV $INST_DIR/$EFI_NEW_LOCATION

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1

# Генерация fstab
genfstab -U $INST_DIR >> $INST_DIR/etc/fstab

#если массив CRYPT_VOLUMES существует
if [[ -v CRYPT_VOLUMES[@] ]]; then
    for ((i=0; i<${#CRYPT_VOLUMES[@]}; i++)); do
        lv_name="${CRYPT_VOLUMES[i]}"
        #Настройка зашифрованного раздела
        echo "cryptroot UUID=$(blkid -s UUID -o value $lv_name) none luks" >> $INST_DIR/etc/crypttab
        echo "GRUB_CMDLINE_LINUX=\"cryptdevice=$lv_name:cryptroot root=/dev/mapper/cryptroot\"" >> $INST_DIR/etc/default/grub

    done
fi


#копирование дополнительных файлов, для выполнения внутри системы (должны быть в одном каталоге с этим)
cp $SCRIPT_DIR/$CHROOT_SCRIPT $INST_DIR
cp $SCRIPT_DIR/$XML_PARSER $INST_DIR
cp $SCRIPT_DIR/$XML_FILE $INST_DIR

#получаем список архивов для распаковки в домашнюю папку пользователя
ARCHIVES_4HOME="$(parse_xml softpack get_archs4home)"

#копирование и распоковка архивов с файлами для домашнего каталога (будут распаковываны в chroot'е)
for archive in $ARCHIVES_4HOME; do
    cp $SCRIPT_DIR/$archive $INST_DIR
done

#-------------------------------
# Chroot в новую систему
# передаём в скрипт idшники установки и имя загрузчика в EFI-разделе
arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SOFTPACK_ID\" \"$DRIVERSPACK_ID\" \"$INSTALL_LOCATION_ID\" \"$SETTINGS_ID\" \"$EFI_SYS_NAME\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/$CHROOT_SCRIPT
rm $INST_DIR/$XML_PARSER
rm $INST_DIR/$XML_FILE


#размонтируем раздел EFI
umount $INST_DIR/$EFI_NEW_LOCATION

# Размонтирование всех разделов
umount -R $INST_DIR
if [ -z "$(ls -A $INST_DIR)" ]; then
    rmdir $INST_DIR
else
    echo -e "${RED}Каталог $INST_DIR не пустой. Удаление не выполнено.${NC}"
fi

#размонтирование всех разделов btrfs
for btrfs_path in "${ALL_ROOT_BTRFS_MOUNTPOINTS[@]}"; do
    umount "$btrfs_path"
done
#удаление пустых каталогов точек монтирования
for btrfs_path in "${ALL_ROOT_BTRFS_MOUNTPOINTS[@]}"; do
    rmdir "$btrfs_path"
done

#если массив CRYPT_VOLUMES существует
if [[ -v CRYPT_VOLUMES[@] ]]; then
    #проходим по массиву CRYPT_VOLUMES в обратном порядке и закрываем зашифрованные тома
    for ((i=${#CRYPT_VOLUMES[@]}-1; i>=0; i--)); do
        lv_name="${CRYPT_VOLUMES[i]}"
        cryptsetup close /dev/mapper/crypt_$(basename "$lv_name")
    done
fi

echo -e "${GREEN}ALL DONE${NC}"


if [[ $INSTALL_FROM == "other_system" ]]; then
    echo "не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)"
    read -p "Нажмите Enter для выхода..."
else
    echo "Установка завершена. Перезагрузите компьютер."
fi

