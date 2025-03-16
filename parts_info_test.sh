#!/bin/bash

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mERROR: This script must be run as root\033[0m" >&2
    exit 1
fi

#цветные переменные
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
PURPLE='\033[35m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
GRAY='\033[90m'
BOLD='\033[1m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
ORANGE='\033[38;5;208m'
NC='\033[0m'

#файл с xml-данными
XML_PARSER="get_data_from_components_xml.py"


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

# Выбор места установки
#INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID места установки")
INSTALL_LOCATION_ID="main_nvidia_gnome"
echo -e "${GREEN}Выбрано место установки: $INSTALL_LOCATION_ID${NC}"


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

get_device_basename4lsblk() {
    local device=$1
    # Определяем формат устройства btrfs
    local device_format=""
    
    # Проверяем формат устройства: /dev/name, /dev/mapper/vgname-name или /dev/vgname/name
    if [[ "$device" =~ ^/dev/[a-zA-Z0-9]+$ ]]; then
        # Формат /dev/name (например, /dev/sda1)
        device_format="standard"
    elif [[ "$device" =~ ^/dev/mapper/[a-zA-Z0-9_]+-[a-zA-Z0-9_]+$ ]]; then
        # Формат /dev/mapper/vgname-name (LVM через mapper)
        device_format="mapper"
    elif [[ "$device" =~ ^/dev/[a-zA-Z0-9_]+/[a-zA-Z0-9_]+$ ]]; then
        # Формат /dev/vgname/name (LVM через vgname)
        device_format="vgpath"
    else
        # Неизвестный формат
        echo -e "${RED}Устройство $device имеет неизвестный формат${NC}" >&2
        return
    fi
    case "$device_format" in
        "standard"|"mapper")
            device_basename=$(basename "$device")
            ;;
        "vgpath")
            #приводим к формату, который используется в lsblk
            device_vgname=$(echo "$device" | awk -F'/' '{print $3}')
            device_lvname=$(echo "$device" | awk -F'/' '{print $4}')
            device_basename="$device_vgname-$device_lvname"
            ;;
    esac
    echo "$device_basename"
}

#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS
#массив котырый будет содержать временные точки монтирования btrfs подлежащие размонтированию в конце работы скрипта
declare -a SOME_BTRFS_MOUNTPOINTS_TO_UNMOUNT

get_btrfs_mountpoint() {
    local btrfs_device=$1 #требуется указать полный путь к устройству
    local btrfs_mountpoint=""
    
    #проверяем есть ли запись в массиве ALL_BTRFS_MOUNTPOINTS
    if [[ -n "${ALL_BTRFS_MOUNTPOINTS[$btrfs_device]}" ]]; then
        btrfs_mountpoint="${ALL_BTRFS_MOUNTPOINTS[$btrfs_device]}"
    else
        #при помощи команды findmnt проверяем, существует ли хотя бы одна точка монтирования для данного устройства
        if ! findmnt "$btrfs_device" > /dev/null 2>&1; then
            #создаём временный каталог
            btrfs_mountpoint=$(mktemp -d)
            #монтируем устройство в временный каталог
            mount "$btrfs_device" "$btrfs_mountpoint"
            #проверяем, что устройство успешно смонтировалось
            if ! findmnt "$btrfs_device" > /dev/null 2>&1; then
                echo -e "${RED}Устройство $btrfs_device не смонтировалось${NC}" >&2
                exit 1
            fi
        else
            #получаем точку монтирования для устройства (первую попавшуюся, если их несколько)
            btrfs_mountpoint=$(findmnt -l -n -o TARGET "$btrfs_device" | sed -n '1p')
        fi
        #добавляем точку монтирования в массив ALL_BTRFS_MOUNTPOINTS
        ALL_BTRFS_MOUNTPOINTS[$btrfs_device]="$btrfs_mountpoint"
    fi
    echo "$btrfs_mountpoint"
}

get_btrfs_subvolumes() {
    local btrfs_device=$1
    #получаем точку монтирования для устройства
    local btrfs_mountpoint=$(get_btrfs_mountpoint "$btrfs_device")

    local subvolumes="$(btrfs subvolume list "$btrfs_mountpoint" | grep 'level 5 path' | sed -E 's/.*level 5 path[[:space:]]+([^[:space:]]+).*/\1/')"
    echo "$subvolumes"
}

echo -e "${CYAN}Общая информация:${NC}"
echo -e "${YELLOW}список разделов до начала установки:${NC}"
lsblk -o NAME,FSTYPE,SIZE,RM,RO,MOUNTPOINTS
#lvs -o vg_name,lv_name,lv_size,lv_attr


#создаём временный файл и сохраняем имя в переменную
LSBLK_RAW_INFO=$(mktemp)
#записываем содержимое во временный файл
lsblk -o NAME,FSTYPE,SIZE,RM,RO,MOUNTPOINTS > $LSBLK_RAW_INFO

#получаем информацию содержащуюся в xml-файле
NEW_MOUNTPOINTS_AMOUNT=$( parse_xml "install_location" "get_amount_of_new_mountpoints")
echo -e "${YELLOW}Количество новых точек монтирования:${NC} $NEW_MOUNTPOINTS_AMOUNT"

#создаём массив для хранения информации о новых точках монтирования
declare -a NEW_MOUNTPOINTS

for ((i=0; i<$NEW_MOUNTPOINTS_AMOUNT; i++)); do
    NEW_MOUNTPOINT=$( parse_xml "install_location" "get_new_mountpoint" "$i")
    #echo "$NEW_MOUNTPOINT"
    CURRENT_POINT_NAME="new_point$i"
    declare -A "$CURRENT_POINT_NAME"
    #получаем ассоциативный массив из строки
    eval "$CURRENT_POINT_NAME=$NEW_MOUNTPOINT"
    NEW_MOUNTPOINTS+=("$CURRENT_POINT_NAME")
done

for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    #преобразуем строку type в массив с разделителем "_in_"
    read -r -a types <<< "${type//_in_/ }"
    crypt_mode=${current_row["crypt_mode"]}
    name=${current_row["name"]}
    #преобразуем строку name в массив с разделителем "_in_"
    read -r -a names <<< "${name//_in_/ }"
    echo -e "${YELLOW}Точка монтирования $row:${NC} $mount_point $type $crypt_mode $name"
    echo "Тип монтирования: $type"
    case "$crypt_mode" in
        "none"|"none_in_none")    
        case "$type" in
            "format_ext4")
                :
                ;;
            "new_subvol_in_btrfs")
                :
                ;;
            "new_subvol_in_btrfs_in_lvm")
                :
                ;;
            "new_ext4_in_lvm")
                :
                ;;
        esac
            ;;
        *)
            echo -e "${RED}Данный функционал пока не реализован: $crypt_mode${NC}"
            ;;
    esac
done


read -p "Нажмите Enter для продолжения"

echo ""

print_all_btrfs_devices() {
    #проходим по содержимому нового вывода команды lsblk посторочно в цикле
    while IFS= read -r line; do
        #если первое слово в строке - btrfs, то выводим второе имя с добавлением нужного префикса перед ним
        if [[ "$line" =~ ^[[:space:]]*btrfs[[:space:]]+lvm ]]; then
            echo "/dev/mapper/$(echo "$line" | awk '{print $3}')"
        elif [[ "$line" =~ ^[[:space:]]*btrfs[[:space:]]+part ]]; then
            echo "/dev/$(echo "$line" | awk '{print $3}')"
        fi
    done < <(lsblk -l -n -o FSTYPE,TYPE,NAME)
    echo ""
}

#print_all_btrfs_devices

print_all_btrfs_subvolumes() {
    #проходмся по выводу функции print_all_btrfs_devices
    for device in $(print_all_btrfs_devices); do
        #выводим подсводы для каждого устройства
        echo -e "${YELLOW}Сабволюмы для устройства $device:${NC}"
        #используем функцию get_btrfs_subvolumes
        #если вывод пустой, то выводим сообщение об отсутствии сабволюмов
        if [[ -z "$(get_btrfs_subvolumes "$device")" ]]; then
            echo -e "${GRAY}${ITALIC}${UNDERLINE}На устройстве $device нет сабволюмов${NC}"
        else
            #выводим сабволюмы
            get_btrfs_subvolumes "$device"
        fi
        echo ""
    done
}

echo -e "${CYAN}Информация о найденных устройствах с файловой системой btrfs:${NC}"
print_all_btrfs_subvolumes


read -p "Нажмите Enter для продолжения"

echo ""
echo -e "${CYAN}Информация о вносимых изменениях:${NC}"
echo -e "${GRAY}${ITALIC}${UNDERLINE}В процессе разработки...${NC}"





echo ""
read -p "Нажмите Enter для продолжения"



#размонтируем временные точки монтирования btrfs
for mountpoint in "${SOME_BTRFS_MOUNTPOINTS_TO_UNMOUNT[@]}"; do
    umount "$mountpoint"
done
#удаляем временные файлы
rm -f $LSBLK_RAW_INFO

exit 0




