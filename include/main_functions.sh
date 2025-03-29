#!/bin/bash
#архиважная функция очистки для заворачивания в trap
cleanup_all(){
    #размонтируем временные точки монтирования btrfs
    if [ -f /tmp/btrfs_temp_mounts.txt ]; then
        echo -e "${CYAN}Список временных точек монтирования:${NC}"
        cat /tmp/btrfs_temp_mounts.txt
    
        while read -r mountpoint; do
            if [ -z "$mountpoint" ]; then
                continue
            fi
        
            echo -e "${GRAY}${ITALIC}${UNDERLINE}Размонтируем точку монтирования $mountpoint${NC}"
            if umount "$mountpoint"; then
                echo -e "${GREEN}Успешно размонтировано: $mountpoint${NC}"
                # Удаляем временный каталог, если он был создан с помощью mktemp
                if [[ "$mountpoint" == /tmp/tmp.* ]]; then
                    rmdir "$mountpoint" 2>/dev/null
                fi
            else
                echo -e "${RED}Ошибка при размонтировании: $mountpoint${NC}"
                echo -e "${YELLOW}Попробуем принудительное размонтирование...${NC}"
                if umount -f "$mountpoint"; then
                    echo -e "${GREEN}Успешно размонтировано с флагом -f: $mountpoint${NC}"
                    # Удаляем временный каталог, если он был создан с помощью mktemp
                    if [[ "$mountpoint" == /tmp/tmp.* ]]; then
                        rmdir "$mountpoint" 2>/dev/null
                    fi
                else
                    echo -e "${RED}Не удалось размонтировать даже с флагом -f: $mountpoint${NC}"
                    echo -e "${YELLOW}Проверьте, не используются ли файлы на этой точке монтирования.${NC}"
                    lsof | grep "$mountpoint" || echo "Файлы не найдены в использовании"
                fi
            fi
        done < /tmp/btrfs_temp_mounts.txt
    
        # Очищаем файл
        > /tmp/btrfs_temp_mounts.txt
    else
        echo -e "${YELLOW}Нет временных точек монтирования для размонтирования${NC}"
    fi
    #cleanup_dummy_device
    #if [[ -n $dummy_dev ]]; then
        ##парсим имя файла из комманды
        #filename=$(losetup $dummy_dev | sed -n 's/.*(\(.*\))/\1/p')
        #losetup -d $dummy_dev

        #if [[ -f "$filename" ]]; then
            #echo "Удаляем файл: $filename"
            #rm -f "$filename"
        #else
            #echo -e "${RED}Ошибка: файл $filename не существует${NC}" >&2
        #fi
    #fi

    #удаляем временные файлы
    rm -f $LSBLK_RAW_INFO
    rm -f $LSBLK_RAW_INFO_UPDATED

    #закрываем открытые крипто-контейнеры с проверкой и выводом сообщений об успешном закрытии или ошибке
    for device in "${!OPENED_CRYPT_CONTAINERS[@]}"; do
        cryptsetup luksClose "${OPENED_CRYPT_CONTAINERS[$device]}"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Крипто-контейнер $device успешно закрыт${NC}"
        else
            echo -e "${RED}При попытке закрыть крипто-контейнер $device возникла ошибка${NC}" >&2
        fi
    done
}


# Функция для проверки существования указанного install_location_id
check_install_location_exists() {
    local id="$1"
    # Напрямую вызываем парсер, так как переданный ID не является текущим INSTALL_LOCATION_ID
    if [[ -n "$(python3 $XML_PARSER install_location "$id" check_id_exists 2>/dev/null)" ]]; then
        return 0  # ID существует
    else
        return 1  # ID не существует
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
    read -p "${prompt_text}: " component_id
    
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
            
            read -p "${prompt_text}: " component_id
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
#standardize_lvm_format_oldversion() {
    #local device=$1
    ##если в начале строки стоит /dev/mapper/, то преобразуем её в реальный формат
    #if [[ "$device" =~ ^/dev/mapper/ ]]; then
        ##получаем имя группы (убрав лишние символы пробелов и табуляций)
        #vg_name=$(safe_lvs --noheading -o vg_name "$device" | tr -d ' ')
        #lv_name=$(safe_lvs --noheading -o lv_name "$device" | tr -d ' ')
        #echo "/dev/$vg_name/$lv_name"
    #else
        #echo "$device"
    #fi
#}

# Функция для преобразования формата mapper в реальный формат с использованием регулярных выражений
# Можно использовать для преобразования формата mapper в реальный формат для устройств, которые не существуют
# ВНИМАНИЕ !!! ДАННУЮ ФУНКЦИЮ НЕЛЬЗЯ ИСПОЛЬЗОВАТЬ с /dev/mapper/* томами открытыми из luks, она только для логических томов lvm
standardize_lvm_format() {
    local device=$1
    #если в начале строки стоит /dev/mapper/, то преобразуем её в реальный формат
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        device_basename=$(basename "$device")
        # Регулярное выражение для извлечения имен групп томов и логических томов
        vg_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\1/')
        lv_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\2/')
        #заменяем все двойные дефисы на один
        vg_name=$(echo "$vg_name" | sed 's/--/-/g')
        lv_name=$(echo "$lv_name" | sed 's/--/-/g')
        echo "/dev/$vg_name/$lv_name"
    else
        echo "$device"
    fi
}

#функция для сравнения двух устройств, учитывающая особые случаи:
#1. если устройства это логические тома lvm могут быть одинаковыми, но иметь разный формат имени: через mapper или через vgname
#2. если если устройство это то что лежит в крипто-контейнере, то нужно сравнивать то что прописано в настройках
# c именем устройства самого lusk, не рездела, который но открывает

#compare_devices() {
    #local device1=$1
    #local device2=$2
    #if [[ "$device1" == "$device2" ]]; then
        #echo "true"
    #else
    
#}




# вместо функций convert_mapper* нужно перейти на get_vg_name_from_fulldevname и get_lv_name_from_fulldevname,
# использующих регексы для извлечения имени группы томов и имени логического тома из полного имени устройства
# нужно учитывать как варианты с /dev/mapper/ так и варианты без него
get_vg_or_lv_name_from_fulldevname() {
    local device=$1
    local type=$2
    #если в начале строки стоит /dev/mapper/
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        device_basename=$(basename "$device")
        # Регулярное выражение для извлечения имен групп томов и логических томов
        vg_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\1/')
        lv_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\2/')
        #заменяем все двойные дефисы на один
        vg_name=$(echo "$vg_name" | sed 's/--/-/g')
        lv_name=$(echo "$lv_name" | sed 's/--/-/g')
    else
        vg_name=$(echo "$device" | sed -r 's|/dev/([^/]+)/([^/]+)$|\1|')
        lv_name=$(echo "$device" | sed -r 's|/dev/([^/]+)/([^/]+)$|\2|')
    fi
    case "$type" in
        "vg") echo "$vg_name" ;;
        "lv") echo "$lv_name" ;;
        *) echo "Ошибка: неизвестный тип '$type'" >&2; exit 1 ;;
    esac
}

get_lv_name_from_fulldevname() {
    local device=$1
    output=$(get_vg_or_lv_name_from_fulldevname "$device" "lv")
    echo $output
}

get_vg_name_from_fulldevname() {
    local device=$1
    output=$(get_vg_or_lv_name_from_fulldevname "$device" "vg")
    echo $output
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
            
            # Сохраняем точку монтирования в файле для последующего размонтирования
            echo "$btrfs_mountpoint" >> /tmp/btrfs_temp_mounts.txt
            
            # Выводим сообщение в stderr, чтобы не влиять на вывод функции
            echo -e "${GRAY}${ITALIC}Добавлена временная точка монтирования: $btrfs_mountpoint${NC}" >&2
            
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
    if safe_pvs "$device_name" &>/dev/null; then
        # Получаем имя группы томов для данного физического тома
        vg_name=$(safe_pvs --noheadings -o vg_name "$device_name" | tr -d ' ')
        
        # Проверяем, не пустое ли имя группы томов
        if [[ -z "$vg_name" || "$vg_name" == "" ]]; then
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
    #именно на этом этапе возникает ошибка для крипто-контейнеров, поскольку они как и логические тома lvm-ов тоже
    #находятся в каталоге /dev/mapper/ но имеют другой формат имени
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        type=${current_row["type"]}
        name=${current_row["name"]}
        #преобразуем строку name в массив с разделителем "_in_"
        read -r -a names <<< "${name//_in_/ }"
        mount_point=${current_row["mount_point"]}
        crypt_mode=${current_row["crypt_mode"]}

        if [[ "$crypt_mode" = *"file"* || "$crypt_mode" = *"pwd"* ]]; then
            #echo "crypto container detected" > /dev/tty
            current_check_device="${current_row["opened_crypt_container_fullname"]}"
            #возращаем исходное значение функции которое точно не сломано функцией convert_mapper 
            current_device=$device
        else
            current_check_device="${names[1]}"
            #это на тот случай если пользователь пропишет имя устройства через mapper
            current_check_device=$(standardize_lvm_format "$current_check_device")
            #помещено сюда, чтобы избежать преобразований для luks т.к. тогда случай с mapper будет разобран не правильно
            current_device=$(standardize_lvm_format "$device")
        fi
        
        
        #если тип монтирования - new_subvol_in_btrfs_in_lvm или new_subvol_in_btrfs
        if [[ "$type" == "new_subvol_in_btrfs_in_lvm" || "$type" == "new_subvol_in_btrfs" ]]; then
            #echo -e "${CYAN}Передано в функцию:${NC} $device" > /dev/tty
            #echo -e "${BLUE}Получено из ассоциативного массива:${NC} $current_check_device" > /dev/tty
            #если имя устройства совпадает с именем устройства в из xml-файла, то добавляем в output
            if [[ "$current_device" == "$current_check_device" ]]; then
                output="$output +${names[0]}->$mount_point"
            fi
        fi
    done
    #echo "$output" > /dev/tty
    echo -e "$output"

}

get_new_lvm_volumes_for_group_with_their_mount_points() {
    local vg_name=$1
    local output=""
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        mount_point=${current_row["mount_point"]}
        type=${current_row["type"]}
        crypt_mode=${current_row["crypt_mode"]}
        read -r -a names <<< "${current_row["name"]//_in_/ }"
        #преобразуем имя устройства в реальный формат
        #current_device_name=$(convert_mapper_format_to_real_format_with_regex "${names[0]}")
        #получаем имя группы томов из имени устройства используя регулярное выражение
        #current_vg_name=$(echo "$current_device_name" | sed -E 's|/dev/([^/]+)/[^/]+$|\1|')
        current_device_name=${names[0]}
        current_vg_name=$(get_vg_name_from_fulldevname "$current_device_name")
        #если тип монтирования - new_ext4_in_lvm
        if [[ "$type" == "new_ext4_in_lvm" ]]; then
            #если группы томов совпадают, то добавляем в output
            if [[ "$vg_name" == "$current_vg_name" ]]; then
                current_basename=$(echo "$current_device_name" | sed -E 's|/dev/[^/]+/([^/]+)$|\1|')
                output="$output +${current_basename}->$mount_point"
            fi
        fi
    done
    echo -e "$output"
}

check_ext4_partitions_to_format_with_their_mount_points() {
    local device=$1
    local output=""
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        mount_point=${current_row["mount_point"]}
        type=${current_row["type"]}
        #преобразуем строку type в массив с разделителем "_in_"
        read -r -a types <<< "${type//_in_/ }"
        crypt_mode=${current_row["crypt_mode"]}
        read -r -a names <<< "${current_row["name"]//_in_/ }"
        #преобразуем имя устройства в реальный формат
        current_device_name=${names[0]}
        #если тип монтирования - new_ext4_in_lvm
        if [[ "$type" == "format_ext4" ]]; then
            #если имя устройства совпадает с именем устройства в массиве names[0], то добавляем в output
            if [[ "$device" == "$current_device_name" ]]; then
                #т.к. девайс только один, сразу присваиваем значение
                output="${GREEN}${BLINK}${BOLD}$current_device_name${NC} ${RED}${UNDERLINE}планируется отформатировать${NC} ${GREEN}в ext4${NC} ${RED}${UNDERLINE}для монтирования в${NC} ${GREEN}${BLINK}${BOLD}$mount_point${NC}"
            fi
        fi
    done
    echo "$output"
}

# Безопасный вызов pvs без утечек дескрипторов
safe_pvs() {
    # Экспортируем переменную, которая указывает LVM не выводить предупреждения о дескрипторах
    export LVM_SUPPRESS_FD_WARNINGS=1
    # Вызываем pvs с переданными аргументами
    pvs "$@"
    local ret_val=$?
    # Снимаем переменную окружения
    unset LVM_SUPPRESS_FD_WARNINGS
    return $ret_val
}

# Безопасный вызов lvs без утечек дескрипторов
safe_lvs() {
    # Экспортируем переменную, которая указывает LVM не выводить предупреждения о дескрипторах
    export LVM_SUPPRESS_FD_WARNINGS=1
    # Вызываем lvs с переданными аргументами
    lvs "$@"
    local ret_val=$?
    # Снимаем переменную окружения
    unset LVM_SUPPRESS_FD_WARNINGS
    return $ret_val
}

#create_btrfs_dummy_device() {
    #local size="${1:-100M}"                         # Размер по умолчанию
    #local img_file loop_dev

    ## Создание временного файла
    #img_file="$(mktemp --tmpdir=/tmp dummy.XXXXXX.img)"
    #fallocate -l "$size" "$img_file"

    ## Подключение loop-устройства
    #loop_dev=$(losetup -f)
    #losetup "$loop_dev" "$img_file"

    ## Форматирование в Btrfs с --mixed для экономии места
    #mkfs.btrfs -q -f --mixed "$loop_dev"

    ## Экспорт для последующего удаления
    #export DUMMY_IMG="$img_file"
    #export DUMMY_LOOP="$loop_dev"

    ## Возврат пути к loop-устройству
    #echo "$loop_dev"
#}

open_crypt_container_by_pwd(){
    local device_name="$1"
    local opened_crypt_container_name="$2"

    # Попытка открыть LUKS-контейнер с ограничением количества попыток
    # все три попытки ввода пароля через cryptsetup luksOpen засчитываются за одну попытку
    local max_attempts=1
    local attempts=0
    local success=false
        
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        ((attempts++))
        #echo -e "${YELLOW}Попытка $attempts из $max_attempts. Введите пароль для контейнера $device_name${NC}"
            
        if cryptsetup luksOpen "$device_name" "$opened_crypt_container_name"; then
            success=true
            echo -e "${GREEN}Крипто-контейнер LUKS успешно открыт${NC}"
        else
            status=$?
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${RED}Ошибка ($status): Не удалось открыть крипто-контейнер LUKS. Пожалуйста, попробуйте снова.${NC}"
            else
                echo -e "${RED}Превышено количество попыток открытия крипто-контейнера LUKS.${NC}" >&2
            fi
        fi
    done
        
    # Проверяем, был ли успешно открыт контейнер
    if [ "$success" = true ]; then
        # сохраняем имя в ассоциативный массив
        OPENED_CRYPT_CONTAINERS["$device_name"]="$opened_crypt_container_name"
        # дописываем поля для последующего быстрого доступа
        current_row["opened_crypt_container_name"]="$opened_crypt_container_name"
        current_row["opened_crypt_container_fullname"]="/dev/mapper/$opened_crypt_container_name"
    else
        # Если не удалось открыть контейнер после трех попыток, прерываем выполнение скрипта
        echo -e "${RED}Не удалось открыть крипто-контейнер LUKS $device_name после $max_attempts попыток.${NC}" >&2    
        echo -e "${RED}Прерывание выполнения скрипта.${NC}"
        exit 1
    fi

}

