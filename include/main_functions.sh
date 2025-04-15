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

#Функция для запроса у пользователя ID компонента
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

#Функция для запроса у пользователя выхода из программы
ask_user_to_exit() {
    local question=$1
    #local error_message=$2
    echo "$question (y/n)"
    read -r exit_choice
    if [[ "$exit_choice" == "y" || "$exit_choice" == "Y" ]]; then
        exit 1
    fi
}

#Функция для замены переносов строк на пробелы
one_line() {
    # Получаем данные из первого аргумента
    local input_data="$1"
    
    # Заменяем переносы строк на запятую
    echo "$input_data" | tr '\n' ' ' | sed 's/ $//'
}

# Функция для замены переносов строк на запятую (скорее всего, не будет использоваться)
one_line_with_commas() {
    # Получаем данные из первого аргумента
    local input_data="$1"
    
    # Заменяем переносы строк на запятую
    echo "$input_data" | tr '\n' ',' | sed 's/,$//'
}


# Функция для преобразования формата mapper в реальный формат с использованием регулярных выражений
# Можно использовать для преобразования формата mapper в реальный формат для устройств, которые не существуют
# ВНИМАНИЕ !!! ДАННУЮ ФУНКЦИЮ НЕЛЬЗЯ ИСПОЛЬЗОВАТЬ с /dev/mapper/* томов открытых из luks, она только для логических томов lvm
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

#Функция для получения имени логического тома из полного имени устройства
#(без проверки на существование устройства т.к. может быть использовано для имён устройств,
#которые пока ещё не созданы)
get_lv_name_from_fulldevname() {
    local device=$1
    #если в начале строки стоит /dev/mapper/
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        device_basename=$(basename "$device")
        # Регулярное выражение для извлечения имен групп томов и логических томов
        lv_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\2/')
        #заменяем все двойные дефисы на один
        lv_name=$(echo "$lv_name" | sed 's/--/-/g')
    else
        lv_name=$(echo "$device" | sed -r 's|/dev/([^/]+)/([^/]+)$|\2|')
    fi
    echo $lv_name
}

#Функция для получения имени группы томов из полного имени устройства
#(без проверки на существование устройства т.к. может быть использовано для имён устройств,
#которые пока ещё не созданы)
get_vg_name_from_fulldevname() {
    local device=$1
    #если в начале строки стоит /dev/mapper/
    if [[ "$device" =~ ^/dev/mapper/ ]]; then
        device_basename=$(basename "$device")
        # Регулярное выражение для извлечения имен групп томов и логических томов
        vg_name=$(echo "$device_basename" | sed -r 's/(.*[^-])-([^-].*)/\1/')
        #заменяем все двойные дефисы на один
        vg_name=$(echo "$vg_name" | sed 's/--/-/g')
    else
        vg_name=$(echo "$device" | sed -r 's|/dev/([^/]+)/([^/]+)$|\1|')
    fi
    echo $vg_name
}

#Функция для окрашивания текста в строке (заглушка-оболочка над конкретной реализацией)
color_text_in_string() {
    local original_string="$1"    # Исходная строка
    local text_to_color="$2"      # Текст, который нужно окрасить
    local color_code="$3"         # Код цвета для окрашивания
    # используем работающий вариант функции
	# добавляем пробелы т.к. они нужны во всех случаях использования данной функции
    color_text_in_string_awk "$original_string" " $text_to_color " "$color_code"
}

# Функция для окрашивания текста в строке с поддержкой UTF-8 (awk)
color_text_in_string_awk() {
    local original_string="$1"    # Исходная строка
    local text_to_color="$2"      # Текст, который нужно окрасить
    local color_code="$3"         # Код цвета для окрашивания
    
    # Используем awk для замены текста с сохранением кодировки
    echo "$original_string" | awk -v text="$text_to_color" -v color="$color_code" -v reset="$NC" '{
        # Функция gsub заменяет все вхождения подстроки
        gsub(text, color text reset);
        print;
    }'
}

#Функция для получения базового имени устройства каким оно отображается в выводе команды lsblk
get_device_basename4lsblk() {
    local device=$1
    # Определяем формат устройства
    local device_format=""
    
    # Проверяем специальный случай для LUKS устройств
    if [[ "$device" =~ ^/dev/mapper/opened_luks_ ]]; then
        # LUKS устройство
        device_basename=$(basename "$device")
        echo "$device_basename"
        return
    fi
    
    # Проверяем формат устройства: /dev/name, /dev/mapper/vgname-name или /dev/vgname/name
    if [[ "$device" =~ ^/dev/[a-zA-Z0-9\.\+_-]+$ ]]; then
        # Формат /dev/name (например, /dev/sda1)
        device_format="standard"
    elif [[ "$device" =~ ^/dev/mapper/[a-zA-Z0-9\.\+_-]+$ ]]; then
        # Формат /dev/mapper/vgname-name (LVM через mapper)
        device_format="mapper"
    elif [[ "$device" =~ ^/dev/[a-zA-Z0-9\.\+_-]+/[a-zA-Z0-9\.\+_-]+$ ]]; then
        # Формат /dev/vgname/name (LVM через vgpath)
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
            
            # Заменяем дефисы на двойные дефисы в именах vg и lv
            device_vgname="${device_vgname//-/--}"
            device_lvname="${device_lvname//-/--}"
            
            device_basename="${device_vgname}-${device_lvname}"
            ;;
    esac
    echo "$device_basename"
}

#Функция для получения точки монтирования для btrfs устройства
#точка монтирования будет автоматически создана, если устройство не смонтировано
#после завершения работы скрипта устройство будет размонтировано засчёт заворачивания в trap
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

#Функция для получения списка сабволюмов для btrfs устройства
#использует внутри себя функцию get_btrfs_mountpoint со всем её функционалом
get_btrfs_subvolumes() {
    local btrfs_device=$1
    #получаем точку монтирования для устройства
    local btrfs_mountpoint=$(get_btrfs_mountpoint "$btrfs_device")

    local subvolumes="$(btrfs subvolume list "$btrfs_mountpoint" | grep 'level 5 path' | sed -E 's/.*level 5 path[[:space:]]+([^[:space:]]+).*/\1/')"
    echo "$subvolumes"
}

#Функция для паузы
make_pause() {
    echo ""
    read -p "Нажмите Enter для продолжения"
    echo ""
}

#Функция для вывода списка всех btrfs устройств (возможно, не будет использоваться)
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

#Функция для вывода списка всех сабволюмов для всех btrfs устройств
#(возможно, не будет использоваться)
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

#Функция для получения списка сабволюмов для устройства с указанием их точек монтирования
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

#Функция для получения списка логических томов для группы томов с указанием их точек монтирования
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

#Функция для проверки наличия ext4 разделов для форматирования с указанием их точек монтирования
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

# Функция для проверки существования группы томов LVM
# Возвращает 0 (успех), если группа существует, 1 (ошибка), если не существует
check_vg_exists() {
    local input="$1"
    local vg_name=""
    
    # Если путь передан в формате /dev/vgname/lvname или /dev/mapper/vgname-lvname
    if [[ "$input" == "/dev/"* ]]; then
        vg_name=$(get_vg_name_from_fulldevname "$input")
    else
        # Иначе считаем, что передано непосредственно имя группы томов
        vg_name="$input"
    fi
    
    # Проверяем существование группы томов с помощью safe_vgs
    if safe_vgs "$vg_name" &>/dev/null; then
        return 0 # Группа существует
    else
        return 1 # Группа не существует
    fi
}
# Функция для проверки существования логического тома
# Название подчёркивается что требуется полное имя устройства
check_lv_exists_by_full_devname() {
    local input="$1"
    local lv_name=""
    local vg_name=""
    
    # Если путь передан в формате /dev/vgname/lvname или /dev/mapper/vgname-lvname
    if [[ "$input" == "/dev/"* ]]; then
        lv_name=$(get_lv_name_from_fulldevname "$input")
        vg_name=$(get_vg_name_from_fulldevname "$input")
    else
        # В этом случае нам нужно знать группу томов
        echo -e "${RED}Ошибка:${NC} Требуется полное имя устройства" >&2
        return 2
    fi
    
    # Проверяем существование логического тома с помощью safe_lvs
    if safe_lvs "$vg_name/$lv_name" &>/dev/null; then
        return 0 # Том существует
    else
        return 1 # Том не существует
    fi
}

#Безопасный вызов vgs без утечек дескрипторов
safe_vgs(){
        # Экспортируем переменную, которая указывает LVM не выводить предупреждения о дескрипторах
    export LVM_SUPPRESS_FD_WARNINGS=1
    # Вызываем lvs с переданными аргументами
    vgs "$@"
    local ret_val=$?
    # Снимаем переменную окружения
    unset LVM_SUPPRESS_FD_WARNINGS
    return $ret_val

}

# Вспомогательная функция для сохранения информации об открытом контейнере
save_crypt_container_info() {
    local device_name="$1"
    local opened_crypt_container_name="$2"
    local key_file="$3"
    
    # Сохраняем имя в ассоциативный массив
    OPENED_CRYPT_CONTAINERS["$device_name"]="$opened_crypt_container_name"
    # Дописываем поля для последующего быстрого доступа
    current_row["opened_crypt_container_name"]="$opened_crypt_container_name"
    current_row["opened_crypt_container_fullname"]="/dev/mapper/$opened_crypt_container_name"
    
    # Если был передан файл-ключ, сохраняем и его
    if [ -n "$key_file" ]; then
        current_row["key_file"]="$key_file"
    fi
}

# Функция для выбора действия пользователем
ask_user_action() {
    local prompt="$1"      # Текст приглашения
    local options="$2"     # Варианты действий, разделенные '|'
    local default_action="$3"  # Действие по умолчанию при некорректном вводе
    
    IFS='|' read -ra opt_array <<< "$options"
    local num_options=${#opt_array[@]}
    
    echo -e "${YELLOW}$prompt${NC}"
    for ((i=0; i<num_options; i++)); do
        local idx=$((i+1))
        if [[ "${opt_array[$i]}" == *"Прервать"* || "${opt_array[$i]}" == *"прервать"* ]]; then
            echo -e "$idx. ${RED}${opt_array[$i]}${NC}"
        else
            echo -e "$idx. ${CYAN}${opt_array[$i]}${NC}"
        fi
    done
    
    read -p "Ваш выбор (1-$num_options): " choice
    
    if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_options" ]; then
        return $((choice-1))
    else
        echo -e "${RED}Некорректный ввод. $default_action${NC}"
        # Возвращаем код для действия по умолчанию
        if [[ "$default_action" == *"Выход"* || "$default_action" == *"выход"* ]]; then
            exit 1
        fi
        return 255  # специальный код для обозначения некорректного ввода
    fi
}

# Функция для выбора и проверки файла-ключа
handle_keyfile_selection() {
    local key_file="$1"
    local action="$2"  # "open" или "create"
    
    # Если путь к файлу-ключу не задан
    if [ -z "$key_file" ]; then
        if [ "$action" = "open" ]; then
            ask_user_action "Путь к файлу-ключу не задан. Выберите действие:" \
                "Ввести путь к файлу-ключу|Использовать пароль вместо файла|Прервать выполнение скрипта" \
                "Пожалуйста, выберите корректное действие."
            
            case $? in
                0)  # Ввести путь
                    read -p "Введите путь к файлу-ключу: " key_file
                    ;;
                1)  # Использовать пароль
                    echo -e "${YELLOW}Переключение на ввод пароля...${NC}"
                    return 1  # Специальный код для переключения на пароль
                    ;;
                2|255)  # Прервать скрипт или некорректный ввод
                    echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                    exit 1
                    ;;
            esac
        else  # action = "create"
            ask_user_action "Путь к файлу-ключу не задан. Выберите действие:" \
                "Ввести путь к файлу-ключу|Создать ключ в стандартном месте (текущий каталог)|Прервать выполнение скрипта" \
                "Пожалуйста, выберите корректное действие."
            
            case $? in
                0)  # Ввести путь
                    read -p "Введите путь к файлу-ключу: " key_file
                    ;;
                1)  # Создать в стандартном месте
                    key_file="./luks_key_$(date +%Y%m%d_%H%M%S).key"
                    echo -e "${GREEN}Файл-ключ будет создан по пути: $key_file${NC}"
                    ;;
                2|255)  # Прервать скрипт или некорректный ввод
                    echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                    exit 1
                    ;;
            esac
        fi
    fi
    
    # Проверка существования файла при открытии
    if [ "$action" = "open" ] && [ ! -f "$key_file" ]; then
        ask_user_action "Файл-ключ '$key_file' не существует. Выберите действие:" \
            "Ввести другой путь к файлу-ключу|Использовать пароль вместо файла|Прервать выполнение скрипта" \
            "Пожалуйста, выберите корректное действие."
        
        case $? in
            0)  # Ввести другой путь
                read -p "Введите путь к файлу-ключу: " new_key_file
                key_file="$new_key_file"
                # Рекурсивно проверяем новый путь
                handle_keyfile_selection "$key_file" "$action"
                return $?
                ;;
            1)  # Использовать пароль
                echo -e "${YELLOW}Переключение на ввод пароля...${NC}"
                return 1  # Специальный код для переключения на пароль
                ;;
            2|255)  # Прервать скрипт или некорректный ввод
                echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                exit 1
                ;;
        esac
    fi
    
    # Проверка существования файла при создании
    if [ "$action" = "create" ] && [ -f "$key_file" ]; then
        ask_user_action "Файл-ключ '$key_file' уже существует. Выберите действие:" \
            "Использовать существующий файл-ключ|Создать резервную копию и пересоздать файл-ключ|Использовать другой путь для файла-ключа|Прервать выполнение скрипта" \
            "Используем существующий файл-ключ."
        
        case $? in
            0)  # Использовать существующий
                echo -e "${GREEN}Используем существующий файл-ключ: $key_file${NC}"
                ;;
            1)  # Создать резервную копию и пересоздать
                backup_file="${key_file}.bak.$(date +%Y%m%d_%H%M%S)"
                if cp "$key_file" "$backup_file"; then
                    echo -e "${GREEN}Создана резервная копия: $backup_file${NC}"
                    rm -f "$key_file"
                    echo -e "${YELLOW}Прежний файл-ключ удалён.${NC}"
                else
                    echo -e "${RED}Не удалось создать резервную копию. Выход.${NC}"
                    exit 1
                fi
                ;;
            2)  # Использовать другой путь
                read -p "Введите новый путь к файлу-ключу: " new_key_file
                key_file="$new_key_file"
                # Рекурсивно проверяем новый путь
                handle_keyfile_selection "$key_file" "$action"
                return $?
                ;;
            3|255)  # Прервать скрипт или некорректный ввод
                if [ $? -eq 255 ]; then
                    echo -e "${GREEN}Используем существующий файл-ключ: $key_file${NC}"
                else
                    echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                    exit 1
                fi
                ;;
        esac
    fi
    
    echo "$key_file"
    return 0
}

# Функция для генерации уникального имени открытого LUKS-контейнера
generate_crypt_container_name() {
    local device_name="$1"
    local basename=$(basename "$device_name") #basename работает с ещё не созданными устройствами, поэтому проблемы тут быть не должно
    local timestamp=$(date +%s_%N)
    local random=$RANDOM
    
    echo "opened_luks_${basename}_${timestamp}_${random}"
}

# Функция для открытия контейнера по паролю
open_crypt_container_by_pwd() {
    local device_name="$1"
    
    # Генерируем имя контейнера с помощью новой функции
    local opened_crypt_container_name=$(generate_crypt_container_name "$device_name")
    
    local max_attempts=1
    local attempts=0
    local success=false
        
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        ((attempts++))
        echo -e "${YELLOW}Попытка $attempts из $max_attempts. Введите пароль для контейнера $device_name${NC}"
            
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
        save_crypt_container_info "$device_name" "$opened_crypt_container_name"
        return 0
    else
        echo -e "${RED}Не удалось открыть крипто-контейнер LUKS $device_name после $max_attempts попыток.${NC}" >&2    
        echo -e "${RED}Прерывание выполнения скрипта.${NC}"
        exit 1
    fi
}

# Функция для открытия контейнера по файлу-ключу
open_crypt_container_by_file() {
    local device_name="$1"
    local key_file="$2"
    
    # Генерируем имя контейнера с помощью новой функции
    local opened_crypt_container_name=$(generate_crypt_container_name "$device_name")
    
    local max_attempts=1
    local attempts=0
    local success=false
    
    # Обрабатываем выбор файла-ключа
    key_file=$(handle_keyfile_selection "$key_file" "open")
    if [ $? -eq 1 ]; then
        # Переключение на пароль
        open_crypt_container_by_pwd "$device_name"
        return $?
    fi
    
    # Пытаемся открыть LUKS-контейнер с помощью файла-ключа
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        ((attempts++))
        echo -e "${YELLOW}Попытка $attempts из $max_attempts. Открываем контейнер $device_name с помощью файла-ключа...${NC}"
        
        if cryptsetup luksOpen --key-file="$key_file" "$device_name" "$opened_crypt_container_name"; then
            success=true
            echo -e "${GREEN}Крипто-контейнер LUKS успешно открыт с помощью файла-ключа${NC}"
        else
            status=$?
            if [ $attempts -lt $max_attempts ]; then
                ask_user_action "Ошибка ($status): Не удалось открыть крипто-контейнер LUKS с помощью файла-ключа. Выберите действие:" \
                    "Попробовать снова с тем же файлом|Ввести другой путь к файлу-ключу|Использовать пароль вместо файла|Прервать выполнение скрипта" \
                    "Попробуем ещё раз с тем же файлом."
                
                case $? in
                    0)  # Продолжаем с тем же файлом
                        ;;
                    1)  # Другой путь к файлу
                        read -p "Введите путь к файлу-ключу: " key_file
                        if [ ! -f "$key_file" ]; then
                            echo -e "${RED}Файл-ключ '$key_file' не существует.${NC}"
                            continue
                        fi
                        ;;
                    2)  # Использовать пароль
                        echo -e "${YELLOW}Переключение на ввод пароля...${NC}"
                        open_crypt_container_by_pwd "$device_name"
                        return $?
                        ;;
                    3|255)  # Прервать или некорректный ввод
                        if [ $? -eq 255 ]; then
                            echo -e "${RED}Некорректный ввод. Попробуем ещё раз с тем же файлом.${NC}"
                        else
                            echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                            exit 1
                        fi
                        ;;
                esac
            else
                echo -e "${RED}Превышено количество попыток открытия крипто-контейнера LUKS.${NC}" >&2
            fi
        fi
    done
    
    # Проверяем, был ли успешно открыт контейнер
    if [ "$success" = true ]; then
        save_crypt_container_info "$device_name" "$opened_crypt_container_name" "$key_file"
        return 0
    else
        echo -e "${RED}Не удалось открыть крипто-контейнер LUKS $device_name после $max_attempts попыток.${NC}" >&2    
        echo -e "${RED}Прерывание выполнения скрипта.${NC}"
        exit 1
    fi
}

# Функция для создания контейнера с новым файлом-ключом
create_and_open_crypt_container_with_new_key_file() {
    local device_name="$1"
    local key_file="$2"
    
    # Генерируем имя контейнера с помощью новой функции
    local opened_crypt_container_name=$(generate_crypt_container_name "$device_name")
    
    local key_size=4096  # Размер ключа по умолчанию в байтах
    
    # Обрабатываем выбор файла-ключа
    key_file=$(handle_keyfile_selection "$key_file" "create")
    
    # Если файл не существует к этому моменту, создаём его
    if [ ! -f "$key_file" ]; then
        echo -e "${YELLOW}Создаём новый файл-ключ: $key_file${NC}"
        
        # Создаём каталог для ключа, если он не существует
        key_dir=$(dirname "$key_file")
        if [ ! -d "$key_dir" ]; then
            mkdir -p "$key_dir" || {
                echo -e "${RED}Не удалось создать каталог для ключа: $key_dir${NC}"
                exit 1
            }
        fi
        
        # Генерируем случайный ключ
        if ! dd if=/dev/urandom of="$key_file" bs=1 count=$key_size status=none; then
            echo -e "${RED}Не удалось создать файл-ключ.${NC}"
            exit 1
        fi
        
        # Устанавливаем права доступа только для владельца
        chmod 600 "$key_file" || {
            echo -e "${RED}Не удалось установить права доступа для файла-ключа.${NC}"
            exit 1
        }
        
        echo -e "${GREEN}Файл-ключ успешно создан.${NC}"
    fi
    
    # Создаём LUKS-контейнер с новым ключом
    echo -e "${YELLOW}Создаём новый LUKS-контейнер на устройстве $device_name...${NC}"
    if ! cryptsetup luksFormat --type luks2 --key-file="$key_file" "$device_name"; then
        echo -e "${RED}Не удалось создать LUKS-контейнер. Выход.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}LUKS-контейнер успешно создан.${NC}"
    
    # Открываем созданный контейнер
    echo -e "${YELLOW}Открываем созданный LUKS-контейнер...${NC}"
    if ! cryptsetup luksOpen --key-file="$key_file" "$device_name" "$opened_crypt_container_name"; then
        echo -e "${RED}Не удалось открыть созданный LUKS-контейнер. Выход.${NC}"
        exit 1
    fi
    
    # Сохраняем информацию о контейнере
    save_crypt_container_info "$device_name" "$opened_crypt_container_name" "$key_file"
    
    echo -e "${GREEN}LUKS-контейнер успешно создан и открыт с помощью файла-ключа.${NC}"
    return 0
}

# Функция для создания контейнера с новым паролем
create_and_open_crypt_container_with_new_pwd() {
    local device_name="$1"
    
    # Генерируем имя контейнера с помощью новой функции
    local opened_crypt_container_name=$(generate_crypt_container_name "$device_name")
    
    local success=false
    local max_attempts=1
    local attempts=0
    
    # Предупреждение пользователю
    echo -e "${YELLOW}ВНИМАНИЕ: Будет создан новый LUKS-контейнер на устройстве $device_name.${NC}"
    echo -e "${RED}Все данные на этом устройстве будут уничтожены!${NC}"
    
    ask_user_action "Вы уверены, что хотите продолжить?" \
        "Да, создать новый LUKS-контейнер|Нет, прервать операцию" \
        "Требуется подтверждение."
    
    case $? in
        1|255)  # Пользователь отказался или некорректный ввод
            echo -e "${YELLOW}Операция отменена пользователем.${NC}"
            return 1
            ;;
    esac
    
    # Создаём LUKS-контейнер с новым паролем
    echo -e "${YELLOW}Создаём новый LUKS-контейнер на устройстве $device_name...${NC}"
    echo -e "${CYAN}Вам потребуется ввести пароль дважды для подтверждения.${NC}"
    
    # Пытаемся создать LUKS-контейнер с паролем
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        ((attempts++))
        if cryptsetup luksFormat --type luks2 --verify-passphrase "$device_name"; then
            success=true
            echo -e "${GREEN}LUKS-контейнер успешно создан.${NC}"
        else
            status=$?
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${RED}Ошибка ($status) при создании LUKS-контейнера.${NC}"
                
                ask_user_action "Выберите действие:" \
                    "Попробовать создать снова|Прервать выполнение скрипта" \
                    "Попробуем ещё раз."
                
                case $? in
                    1|255)  # Пользователь выбрал прервать или некорректный ввод
                        if [ $? -eq 255 ]; then
                            echo -e "${YELLOW}Попробуем ещё раз создать контейнер.${NC}"
                        else
                            echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                            exit 1
                        fi
                        ;;
                esac
            else
                echo -e "${RED}Превышено количество попыток создания LUKS-контейнера.${NC}" >&2
                echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                exit 1
            fi
        fi
    done
    
    # Открываем созданный контейнер
    echo -e "${YELLOW}Открываем созданный LUKS-контейнер...${NC}"
    echo -e "${CYAN}Введите пароль, который вы только что установили.${NC}"
    
    # Сбрасываем счетчики для открытия
    success=false
    attempts=0
    
    # Пытаемся открыть созданный контейнер
    while [ $attempts -lt $max_attempts ] && [ "$success" = false ]; do
        ((attempts++))
        echo -e "${YELLOW}Попытка $attempts из $max_attempts открыть контейнер.${NC}"
        
        if cryptsetup luksOpen "$device_name" "$opened_crypt_container_name"; then
            success=true
            echo -e "${GREEN}LUKS-контейнер успешно открыт.${NC}"
        else
            status=$?
            if [ $attempts -lt $max_attempts ]; then
                echo -e "${RED}Ошибка ($status): Не удалось открыть LUKS-контейнер. Пожалуйста, попробуйте снова.${NC}"
            else
                echo -e "${RED}Превышено количество попыток открытия LUKS-контейнера.${NC}" >&2
                echo -e "${RED}Прерывание выполнения скрипта.${NC}"
                exit 1
            fi
        fi
    done
    
    # Сохраняем информацию о контейнере
    save_crypt_container_info "$device_name" "$opened_crypt_container_name"
    
    echo -e "${GREEN}LUKS-контейнер успешно создан и открыт с паролем.${NC}"
    echo -e "${YELLOW}ВАЖНО: Запомните пароль! Без него вы не сможете получить доступ к данным.${NC}"
    return 0
}

# Функция для проверки существования раздела с указанным UUID и получения пути к нему
check_uuid_exists() {
        # Возвращает:
    #   - путь к устройству через echo, если оно существует
    #   - код возврата 0, если раздел существует
    #   - код возврата 1, если раздел не существует
    #   - код возврата 2, если UUID не указан
    #
    # Примеры использования:
    # 1. Получение пути к устройству:
    #    device_path=$(check_uuid_exists "19d66900-a87a-4784-94b3-18b9916f7997")
    #    if [ $? -eq 0 ]; then
    #        echo "Путь к устройству: $device_path"
    #    fi
    #
    # 2. Проверка существования устройства:
    #    check_uuid_exists "19d66900-a87a-4784-94b3-18b9916f7997" >/dev/null
    #    if [ $? -eq 0 ]; then
    #        echo "Устройство существует"
    #    else
    #        echo "Устройство не существует"
    #    fi
    #
    # 3. Комбинированное использование:
    #    if device_path=$(check_uuid_exists "19d66900-a87a-4784-94b3-18b9916f7997"); then
    #        echo "Устройство существует по пути: $device_path"
    #    else
    #        echo "Устройство не существует"
    #    fi
    # 4. Практическое применение в моём скрипте:
    # if ! device_path=$(check_uuid_exists "19d66900-a87a-4784-94b3-18b9916f7997"); then
    #   #обработка ошибки
    #   continue #переход на следующий шаг в цикле
    # fi
    # #использование device_path
    local uuid="$1"
    local device_path=""
    
    # Проверяем, что UUID не пуст
    if [ -z "$uuid" ]; then
        echo -e "${RED}Ошибка: UUID не указан${NC}" >&2
        return 2
    fi
    
    # Ищем устройство с указанным UUID
    if device_path=$(blkid -U "$uuid" 2>/dev/null); then
        echo "$device_path"  # Выводим путь к устройству для использования в других функциях
        return 0  # Сигнализируем, что раздел существует
    else
        device_path=""  # Явно устанавливаем пустую строку
        return 1  # Сигнализируем, что раздел не существует
    fi
}

