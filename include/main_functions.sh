#!/bin/bash

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


one_line() {
    # Получаем данные из первого аргумента
    local input_data="$1"
    
    # Заменяем переносы строк на запятую
    echo "$input_data" | tr '\n' ' ' | sed 's/ $//'
}

# Функция для замены переносов строк на запятую
one_line_with_commas() {
    # Получаем данные из первого аргумента
    local input_data="$1"
    
    # Заменяем переносы строк на запятую
    echo "$input_data" | tr '\n' ',' | sed 's/,$//'
}

# Функция для преобразования формата mapper в реальный формат
# Работает только для устройств, которые существуют
convert_mapper_format_to_real_format_with_lvs() {
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

# Функция для преобразования формата mapper в реальный формат с использованием регулярных выражений
# Можно использовать для преобразования формата mapper в реальный формат для устройств, которые не существуют
# Но работает также для устройств, которые существуют, поэтому подходит для полноценной замены функции convert_mapper_format_to_real_format_for_device 
convert_mapper_format_to_real_format_with_regex() {
    local device=$1
    #если в начале строки стоит /dev/mapper/, то преобразуем её в реальный формат
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        device_basename=$(basename "$device")
        # Регулярное выражение для извлечения имен групп томов и логических томов
        vg_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\1/')
        lv_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\2/')
        echo "/dev/$vg_name/$lv_name"
    else
        echo "$device"
    fi
}
# Функция для преобразования формата mapper в реальный формат
# Заглушка для замены старого варианта функции на более быструю реализацию
convert_mapper_format_to_real_format_for_device() {
    local device=$1
    output=$(convert_mapper_format_to_real_format_with_regex "$device")
    echo "$output"
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
            #echo -e "${GRAY}${ITALIC}Не принадлежит ни одной группе томов${NC}"
            echo ""
        else
            echo "$vg_name"
        fi
    else
        echo -e "${RED}Устройство $device_name не является физическим томом LVM${NC}" >&2
        exit 1
    fi
}



get_new_btrfs_subvolumes_for_device_with_their_mount_points() {
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
                output="$output ${names[0]}->$mount_point"
            fi
        fi
    done
    echo -e "$output"

}

get_new_lvm_volumes_for_group_with_their_mount_points() {
    local vg_name=$1
    local output=""
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        mount_point=${current_row["mount_point"]}
        type=${current_row["type"]}
        #преобразуем строку type в массив с разделителем "_in_"
        read -r -a types <<< "${type//_in_/ }"
        crypt_mode=${current_row["crypt_mode"]}
        name=${current_row["name"]}
        #преобразуем имя устройства в реальный формат
        name=$(convert_mapper_format_to_real_format_with_regex "$name")
        #получаем имя группы томов из имени устройства используя регулярное выражение
        current_vg_name=$(echo "$name" | sed -E 's|/dev/([^/]+)/[^/]+$|\1|')
        #если тип монтирования - new_ext4_in_lvm
        if [[ "$type" == "new_ext4_in_lvm" ]]; then
            #если группы томов совпадают, то добавляем в output
            if [[ "$vg_name" == "$current_vg_name" ]]; then
                current_basename=$(echo "$name" | sed -E 's|/dev/[^/]+/([^/]+)$|\1|')
                output="$output ${current_basename}->$mount_point"
            fi
        fi
    done
    echo -e "$output"
}