#!/bin/bash

#цветные переменные
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
PURPLE='\033[35m'
BLUE='\033[34m'
MAGENTA='\033[35m'
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

#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS
#массив котырый будет содержать временные точки монтирования btrfs подлежащие размонтированию в конце работы скрипта
declare -a SOME_BTRFS_MOUNTPOINTS_TO_UNMOUNT
get_btrfs_mountpoint() {
    local btrfs_device=$1 #требуется указать полный путь к устройству
    local btrfs_mountpoint=""
    # Определяем формат устройства btrfs
    local btrfs_format=""
    
    # Проверяем формат устройства: /dev/name, /dev/mapper/vgname-name или /dev/vgname/name
    if [[ "$btrfs_device" =~ ^/dev/[a-zA-Z0-9]+$ ]]; then
        # Формат /dev/name (например, /dev/sda1)
        btrfs_format="standard"
    elif [[ "$btrfs_device" =~ ^/dev/mapper/[a-zA-Z0-9_]+-[a-zA-Z0-9_]+$ ]]; then
        # Формат /dev/mapper/vgname-name (LVM через mapper)
        btrfs_format="mapper"
    elif [[ "$btrfs_device" =~ ^/dev/[a-zA-Z0-9_]+/[a-zA-Z0-9_]+$ ]]; then
        # Формат /dev/vgname/name (LVM через vgname)
        btrfs_format="vgpath"
    else
        # Неизвестный формат
        echo -e "${RED}Устройство $btrfs_device имеет неизвестный формат${NC}" > &2
        return
    fi


    
    case "$btrfs_format" in
        "standard"|"mapper")
            btrfs_dev_basename=$(basename "$btrfs_device")
            ;;
        "vgpath")
            #приводим к формату, который используется в lsblk
            btrfs_dev_vgname=$(echo "$btrfs_device" | awk -F'/' '{print $3}')
            btrfs_dev_lvname=$(echo "$btrfs_device" | awk -F'/' '{print $4}')
            btrfs_dev_basename="$btrfs_dev_vgname-$btrfs_dev_lvname"
            ;;
    esac
    
    #TODO: реализовать парсинг lsblk
    
     
    
    
    #проверяем, что устройство является btrfs

    # if ! lsblk -l -o NAME,FSTYPE | grep "$btrfs_dev_basename" | awk '{print $2}' | grep -q "btrfs"; then
        #echo -e "${RED}Устройство $btrfs_device не является btrfs${NC}" > &2
        #return
    #fi
    ##проверяем, существует ли точка монтирования для данного устройства
    #if ! lsblk -l -o NAME,MOUNTPOINTS | grep "$btrfs_dev_basename" | awk '{print $2}' | grep -q "/"; then
        #echo -e "${RED}Точка монтирования для устройства $btrfs_device не найдена${NC}" > &2
        #return
    #fi
    ##local btrfs_mountpoint=$(lsblk -o NAME,FSTYPE,SIZE,RM,RO,MOUNTPOINTS | grep "$btrfs_device" | awk '{print $6}')
    #ALL_BTRFS_MOUNTPOINTS[$btrfs_mountpoint]=$btrfs_mountpoint
}

get_btrfs_subvolumes() {
    local btrfs_device=$1
    #получаем точку монтирования для устройства
    local btrfs_mountpoint=$(get_btrfs_mountpoint "$btrfs_device")
}


echo -e "${YELLOW}список разделов до начала установки:${NC}"
lsblk -o NAME,FSTYPE,SIZE,RM,RO,MOUNTPOINTS
#lvs -o vg_name,lv_name,lv_size,lv_attr


#создаём временный файл и сохраняем имя в переменную
LSBLK_RAW_INFO="/tmp/lsblk_before_install.txt"
touch $LSBLK_RAW_INFO
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



#размонтируем временные точки монтирования btrfs
for mountpoint in "${SOME_BTRFS_MOUNTPOINTS_TO_UNMOUNT[@]}"; do
    umount "$mountpoint"
done

exit 0




