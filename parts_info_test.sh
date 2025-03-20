#!/bin/bash

: << 'TODO'
+ внедрить проверку на то, что имена новых btrfs сабволюмов не совпадают с именами существующих
+ внедрить отображение о планируемых новых разделах lvm
+ внедрить проверку на то, что имена новых lvm томов не совпадают с именами существующих
+ проверять свободное место на диске
+ проверять что все прописанные ext4, lvm, btrfs имеются в разметке
TODO

# Подключаем файл с цветовыми переменными
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

# создаём ассоциативный массив problems для возможного запланированного выхода 
declare -A problems
#вносим значения в массив (пустая строка - означает, что проблемы нет)
problems["no_free_space"]=""
problems["btrfs_subvolume_name_already_exists"]=""
problems["lvm_logical_volume_name_already_exists"]=""
problems["btrfs_device_not_found"]=""
problems["lvm_group_not_found"]=""
problems["ext4_device_not_found"]=""
problems["syntax_problem_in_xml_file"]=""

#флаг для запланрованного выхода из скрипта
exit_and_show_problems_flag=0


#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mERROR: This script must be run as root\033[0m" >&2
    exit 1
fi



# Функция для замены переносов строк на запятую
one_line() {
    # Получаем данные из первого аргумента
    local input_data="$1"
    
    # Заменяем переносы строк на запятую
    echo "$input_data" | tr '\n' ',' | sed 's/,$//'
}

convert_mapper_format_to_real_format_for_device() {
    local device=$1
    #если в начале строки стоит /dev/mapper/, то преобразуем её в реальный формат
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        #получаем имя группы (убрав лишние символы пробелов и табуляций)
        vg_name=$(lvs --noheading -o vg_name $device | tr -d ' ')
        lv_name=$(lvs --noheading -o lv_name $device | tr -d ' ')
        echo "/dev/$vg_name/$lv_name"
    else
        echo "$device"
    fi
}

# Функция для окрашивания указанного текста в строке
color_text_in_string() {
    local original_string="$1"    # Исходная строка
    local text_to_color="$2"      # Текст, который нужно окрасить
    local color_code="$3"         # Код цвета для окрашивания
    
    # Находим позицию текста в строке
    local position=$(echo -n "$original_string" | grep -bo "$text_to_color" | cut -d':' -f1)
    
    # Если текст найден
    if [ -n "$position" ]; then
        # Получаем длину текста
        local text_length=${#text_to_color}
        
        # Разделяем строку на части до и после окрашиваемого текста
        local prefix=$(echo -n "$original_string" | cut -c1-$position)
        local suffix=$(echo -n "$original_string" | cut -c$((position+text_length+1))-)
        
        # Возвращаем строку с окрашенным текстом
        echo "${prefix}${color_code}${text_to_color}${NC}${suffix}"
    else
        # Возвращаем исходную строку, если текст не найден
        echo "$original_string"
    fi
}

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

make_pause() {
    echo ""
    read -p "Нажмите Enter для продолжения"
    echo ""
}

echo -e "${CYAN}Общая информация:${NC}"
echo -e "${YELLOW}список разделов до начала установки:${NC}"
lsblk -o NAME,FSTYPE,SIZE,RM,RO,MOUNTPOINTS
#lvs -o vg_name,lv_name,lv_size,lv_attr



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
done


make_pause



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

# Функция для получения имени группы томов, если устройство является физическим томом LVM
get_vg_name_for_pv() {
    local device_name=$1  # Полный путь к устройству
    local vg_name=""
    
    # Проверяем, является ли устройство физическим томом LVM
    if pvs "$device_name" &>/dev/null; then
        # Получаем имя группы томов для данного физического тома
        vg_name=$(pvs --noheadings -o vg_name "$device_name" | tr -d ' ')
        
        # Проверяем, не пустое ли имя группы томов
        if [[ -z "$vg_name" || "$vg_name" == "" ]]; then
            echo -e "${GRAY}${ITALIC}Не принадлежит ни одной группе томов${NC}"
        else
            echo "$vg_name"
        fi
    else
        echo -e "${RED}Устройство $device_name не является физическим томом LVM${NC}"
    fi
}



get_new_btrfs_subvolumes_for_device() {
    #проходимся по всем точкам монтирования
    local device=$1
    local output=""
    device=$(convert_mapper_format_to_real_format_for_device "$device")
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
        #если тип монтирования - new_subvol_in_btrfs_in_lvm или new_subvol_in_btrfs
        if [[ "$type" == "new_subvol_in_btrfs_in_lvm" || "$type" == "new_subvol_in_btrfs" ]]; then
            #приводим девайсы к единому формату
            names[1]=$(convert_mapper_format_to_real_format_for_device "${names[1]}")
            #если имя устройства совпадает с именем устройства в массиве names[1], то добавляем в output
            if [[ "$device" == "${names[1]}" ]]; then
                output="$output${GREEN}+ ${names[0]} -> $mount_point${NC};"
            fi
        fi
    done
    echo -e "$output"

}

#echo -e "${CYAN}Информация о найденных устройствах с файловой системой btrfs:${NC}"
#print_all_btrfs_subvolumes
#read -p "Нажмите Enter для продолжения"
#echo ""

echo -e "${CYAN}Информация о вносимых изменениях:${NC}"
echo -e "${GRAY}${ITALIC}${UNDERLINE}Построение информации...${NC}"

#можно переделать на последовательные правки файла, а потом его отображение
#нужно подогнать новый раздел по максимальной длине строки

#создаём временный файл и сохраняем имя в переменную
LSBLK_RAW_INFO=$(mktemp)
LSBLK_RAW_INFO_UPDATED=$(mktemp)
#записываем содержимое во временный файл
#RM или RO - нужно дописать в конец строки чтобы при добавлении дополнительного параметра всё было выровнено по правому краю
lsblk -o NAME,TYPE,FSTYPE,SIZE,RM,RO,ROTA > $LSBLK_RAW_INFO

#определяем длину строки в файле
LENGTH_OF_LINE_IN_LSBLK_RAW_INFO=$(wc -L < $LSBLK_RAW_INFO)

#записываем первую строку с добавочным текстом (если нужен) во второй временный файл
#echo "$(head -n 1 $LSBLK_RAW_INFO) SUBVOLUMES" > $LSBLK_RAW_INFO_UPDATED
echo "$(head -n 1 $LSBLK_RAW_INFO)" > $LSBLK_RAW_INFO_UPDATED


#проходися по файлу начиная со второй строки в цикле
while IFS= read -r line; do
    #дублируем строку как есть до изменения
    line_orig="$line"
    #заменяем '│ ' на '│·' чтобы избежать ошибочного разбиения на слова
    line=$(echo "$line" | sed 's/│ /│·/g')
    if [[ "$(echo "$line" | awk '{print $3}')" == "btrfs" ]]; then
        # Используем функцию для окрашивания слова "btrfs"
        line_colored=$(color_text_in_string "$line_orig" "btrfs" "$CYAN")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
        
        #получаем базовое имя устройства
        device_basename=$(echo "$line" | awk '{print $1}')
        #удаляем любые символы отображающие древовидную структуру из начала строки
        device_basename=$(echo "$device_basename" | sed 's/^[├─└│·]*//')
        #определяем полное имя устройства
        if [[ "$(echo "$line" | awk '{print $2}')" == "lvm" ]]; then
            device_fullname="/dev/mapper/$device_basename"
        elif [[ "$(echo "$line" | awk '{print $2}')" == "part" ]]; then
            device_fullname="/dev/$device_basename"
        fi
        #используем функцию get_btrfs_subvolumes
        #если вывод пустой, то выводим сообщение об отсутствии сабволюмов
        if [[ -z "$(get_btrfs_subvolumes "$device_fullname")" ]]; then
            echo -e "${GRAY}${ITALIC}${UNDERLINE}На устройстве $device_fullname нет сабволюмов${NC}" >> $LSBLK_RAW_INFO_UPDATED
        else
            #выводим сабволюмы, используем echo чтобы отобразить их в одной строке, если их несколько
            echo -e "!${BOLD}Имеющиеся сабволюмы:${NC} ${CYAN}$(one_line "$(get_btrfs_subvolumes "$device_fullname")")${NC}" >> $LSBLK_RAW_INFO_UPDATED
        fi
        new_btrfs_subvolumes_string=$(get_new_btrfs_subvolumes_for_device "$device_fullname")
        #если полученная строка не пустая, то выводим её
        if [[ -n "$new_btrfs_subvolumes_string" ]]; then
            echo -e "!${BOLD}Планируемые изменения:${NC} $new_btrfs_subvolumes_string" >> $LSBLK_RAW_INFO_UPDATED
        fi

    elif [[ "$(echo "$line" | awk '{print $3}')" == "LVM2_member" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "LVM2_member" "$YELLOW")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
        #получаем базовое имя устройства
        device_basename=$(echo "$line" | awk '{print $1}')
        #удаляем любые символы отображающие древовидную структуру из начала строки
        device_basename=$(echo "$device_basename" | sed 's/^[├─└│·]*//')
        #определяем полное имя устройства
        device_fullname="/dev/$device_basename"
        #получаем имя группы томов
        vg_name=$(get_vg_name_for_pv "$device_fullname")
        echo -e "!${BOLD}Имя группы томов:${NC} ${YELLOW}$vg_name${NC}" >> $LSBLK_RAW_INFO_UPDATED
    elif [[ "$(echo "$line" | awk '{print $3}')" == "ext4" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "ext4" "$LIGHT_PURPLE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    elif [[ "$(echo "$line" | awk '{print $3}')" == "crypto_LUKS" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "crypto_LUKS" "$LIGHT_BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    else
        #пишем строку как есть
        echo "$line_orig" >> $LSBLK_RAW_INFO_UPDATED
    fi
done < <(sed '1d' $LSBLK_RAW_INFO)

# Обновляем первый временный файл и обнуляем второй
cp $LSBLK_RAW_INFO_UPDATED $LSBLK_RAW_INFO
#выводим содержимое временного файла
cat $LSBLK_RAW_INFO



#добляем на разметку список изменений, которые планируется произвести
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

make_pause

#размонтируем временные точки монтирования btrfs
for mountpoint in "${SOME_BTRFS_MOUNTPOINTS_TO_UNMOUNT[@]}"; do
    umount "$mountpoint"
done
#удаляем временные файлы
rm -f $LSBLK_RAW_INFO
rm -f $LSBLK_RAW_INFO_UPDATED
exit 0




