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
        
            echo -e "${GRAY}Размонтируем точку монтирования $mountpoint${NC}"
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
        rm -f /tmp/btrfs_temp_mounts.txt
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

#Функция для перевода байт в гиги:
convert_bytes_to_gb() {
    local bytes=$1
    echo "$(echo "$bytes / $GB" | bc)G"
}

#Функции для проверки свободного места в группах томов (и в физических томах)
check_free_space_in_vg_in_bytes() {
    local vg_name=$1
    local free_space=$(safe_vgs "$vg_name" --nosuffix --units b | grep VFree | awk '{print $2}')
    echo "$free_space"
}
check_free_space_in_vg_in_human_format() {
    local vg_name=$1
    local free_space=$(safe_vgs "$vg_name" --nosuffix --units h | grep VFree | awk '{print $2}')
    echo "$free_space"
}

check_free_space_in_pv_in_bytes() {
    local pv_name=$1
    local free_space=$(safe_pvs "$pv_name" --nosuffix --units b | grep PFree | awk '{print $2}')
    echo "$free_space"
}

check_free_space_in_pv_in_human_format() {
    local pv_name=$1
    local free_space=$(safe_pvs "$pv_name" --nosuffix --units h | grep PFree | awk '{print $2}')
    echo "$free_space"
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


#Функция для для заполнения ассоциативного массива
#помимо строки с  названием девайса функция принимает на вход
#ссылку на пустой ассоциативный массив, который в ходе выполнения функций будет заполнен
#данными для дальнейшего использования в формате: "имя_планируемого_тома"->"точка_монтирования"

#Данную функцию можно использовать только после этапа открытия крипто-контейнеров
#Т.к. в ней используется поле device_for_operations, которое заполняется только после этого этапа
fill_in_array_by_new_btrfs_subvolumes_for_device() {
    #принимаем на вход имя устройства
    local device_from_input=$1
    #принимаем на вход ссылку на ассоциативный массив
    local -n array_ref=$2
    #полученный массив нужно заполнить в формате: "имя_планируемого_тома"->"точка_монтирования"
    
    #проходимся по всем точкам монтирования
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        type=${current_row["type"]}
        #нас интересуют только эти случаи, всё остальное сразу пропускаем
        if [[ "$type" == "new_subvol_in_btrfs_in_lvm" || "$type" == "new_subvol_in_btrfs" ]]; then 
            subvolume=${current_row["subvolume"]}
            mount_point=${current_row["mount_point"]}
            crypt_mode=${current_row["crypt_mode"]}
            
            current_check_device=${current_row["device_for_operations"]}

            # сравниваем по полным путям или после нормализации LVM
            if [[ "$device_from_input" == "$current_check_device" ]] || \
               [[ "$(standardize_lvm_format \"$device_from_input\")" == "$(standardize_lvm_format \"$current_check_device\")" ]]; then
                array_ref["$subvolume"]="$mount_point"
            fi
        fi
    done
}
#Функция для получения строки с планируемыми изменениями для btrfs
get_string_for_new_btrfs_subvolumes_for_device() {
    local -n array_ref=$1
    local output=""
    for key in "${!array_ref[@]}"; do
        output="$output [ + $key -> ${array_ref[$key]} ]"
    done

    echo "$output"
}

#Функция для заполнения ассоциативных массивов для построения строки с планируемыми изменениями
#В функции для btrfs мы искали совпадение девайсов с btrfs для добавления нового сабволюма туда
#Здесь же мы ищем совпадение групп томов для добавления или нового логического тома или c голой ext4 или с luks
fill_in_array_by_new_lvm_volumes_for_group() {
    #Ответы на пару вопросов, которые у меня возникли при обдумывании этой функции:
    #В каких случаях нужно брать значение device_for_operations, а в каких lv-volume? - во всех случаях lv-volume
    #Т.к. при отсутствии шифрования device_for_operations совпадает с lv-volume,
    #Если шифрование на уровне pv, они также совпадают, если на уровне lv, device_for_operations ещё не создан,
    #И не может быть найден в выводе команды lsblk, нужно всё равно найти lv-volume и отобразить информацию,
    #Что внутри него будет создан luks
    #В каких случаях имя не будет формата lv lvm и функцию get_vg_name_from_fulldevname нужно будет заменить на что-то другое?
    #Ответ: в данной функции не подтребуется замена, т.к. в случае разбраный выше: мы работаем только с тем
    #что найдётся по "lvm" в выводе команды lsblk, crypt и part тут не затрагиваются
    
    #crypt_mode влияет на то, как будет отображена информация пользователю:
    #при crypt_mode = file_in_none и pwd_in_none нужно также уточнить, что будет создан
    #не просто логический том, а luks
    local vg_name_from_input=$1
    local -n array_ref=$2
    local -n array_ref_is_luks=$3
    local output=""
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        type=${current_row["type"]}
        #нас интересуют только эти случаи, всё остальное сразу пропускаем
        if [[ "$type" == "new_ext4_in_lvm" ]]; then

            mount_point=${current_row["mount_point"]}
            crypt_mode=${current_row["crypt_mode"]}
            current_device_name=${current_row["lv-volume"]}
            current_vg_name=$(get_vg_name_from_fulldevname "$current_device_name")
        
            #если группы томов совпадают, то заполняем ассоциативный массив
            if [[ "$vg_name_from_input" == "$current_vg_name" ]]; then
                #лучше использовать функцию т.к. не понятьно в каком формате приходит current_device_name
                #current_basename=$(echo "$current_device_name" | sed -E 's|/dev/[^/]+/([^/]+)$|\1|')
                #current_basename=$(get_device_basename4lsblk "$current_device_name")
                current_basename=$(get_lv_name_from_fulldevname "$current_device_name")
                array_ref["$current_basename"]="$mount_point"
                # по аналогии со статусом возврата в bash: 0 это истина, 1 это ложь
                if [[ "$crypt_mode" == "file_in_none" || "$crypt_mode" == "pwd_in_none" ]]; then
                    array_ref_is_luks["$current_basename"]=0
                else
                    array_ref_is_luks["$current_basename"]=1
                fi
            fi
        fi
    done
}

#Функция для получения строки с планируемыми изменениями для lvm
get_string_for_new_lvm_volumes_for_group() {
    local -n array_ref=$1
    local -n array_ref_is_luks=$2
    local output=""
    for key in "${!array_ref[@]}"; do
        
        if (( "${array_ref_is_luks[$key]}" == 0 )); then
            output="$output [ + $key в новом luks -> ${array_ref[$key]} ]"
        else
            output="$output [ + $key -> ${array_ref[$key]} ]"
        fi
    done
    echo "$output"
}

#Функция для проверки наличия ext4 разделов для форматирования с указанием их точек монтирования
check_ext4_partitions_to_format_with_their_mount_points() {
    local device_from_input=$1
    local output=""
    for row in "${NEW_MOUNTPOINTS[@]}"; do
        declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
        type=${current_row["type"]}
        if [[ "$type" == "format_ext4" ]]; then
        
            mount_point=${current_row["mount_point"]}
            crypt_mode=${current_row["crypt_mode"]}
            current_device_name=${current_row["device"]}

            #если полученное имя устройства совпадает с именем устройства в массиве, то добавляем в output
            if [[ "$device_from_input" == "$current_device_name" ]]; then
                #т.к. девайс только один, сразу присваиваем значение
                if [[ "$crypt_mode" == "file" || "$crypt_mode" == "pwd" ]]; then
                    output="${GREEN}${BLINK}${BOLD}$current_device_name${NC} ${RED}${UNDERLINE}планируется отформатировать${NC} ${GREEN}в крипто-контейнер luck с ext4 внутри ${NC} ${RED}${UNDERLINE}для монтирования в${NC} ${GREEN}${BLINK}${BOLD}$mount_point${NC}"
                else
                    output="${GREEN}${BLINK}${BOLD}$current_device_name${NC} ${RED}${UNDERLINE}планируется отформатировать${NC} ${GREEN}в ext4${NC} ${RED}${UNDERLINE}для монтирования в${NC} ${GREEN}${BLINK}${BOLD}$mount_point${NC}"
                fi
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

# Функция для проверки, открыт ли контейнер и обновлении информации о нём
check_and_update_crypt_container_info() {
    local device_name="$1"
    local map_name=$(lsblk -l -n -o NAME,TYPE,PKNAME | awk -v dev="$bname" '$2=="crypt" && $3==dev {print $1; exit}')
    if [[ -n "$map_name" ]]; then
        echo -e "${YELLOW}${BOLD}Крипто-контейнер для ${GREEN}$device_name${YELLOW} уже открыт в системе как ${GREEN}$map_name${NC}, пропускаем открытие${NC}" > /dev/tty
        OPENED_CRYPT_CONTAINERS["$device_name"]="$map_name"
        save_crypt_container_info "$device_name" "$map_name"
        return 0
    fi
}

# Функция для открытия контейнера по паролю
open_crypt_container_by_pwd() {
    local device_name="$1"

    # Если в системе уже есть открытый LUKS-контейнер для device_name, пропускаем открытие
    check_and_update_crypt_container_info "$device_name"
    #Выходим если проверка сработала
    if [ $? -eq 0 ]; then
        return 0
    fi

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
    
    # Если в системе уже есть открытый LUKS-контейнер для device_name, пропускаем открытие
    check_and_update_crypt_container_info "$device_name"
    #Выходим если проверка сработала
    if [ $? -eq 0 ]; then
        return 0
    fi

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

#функция для проверки проблем и выхода из скрипта
function check_problems() {
    if [[ "$exit_and_show_problems_flag" == 1 ]]; then
        echo -e "${RED}На текущем этапе проверки были выявлены следующие проблемы:${NC}"
        for problem in "${!problems[@]}"; do
            echo -e "$problem: ${RED}${problems[$problem]}${NC}"
        done
        echo ""
        echo -e "${RED}${BOLD}Устраните проблемы и перезапустите скрипт${NC}"
        exit 1
    else
        echo -e "${GREEN}На текущем этапе проверки проблем не выявлено${NC}"
    fi
}

#Функция для запроса формата вывода lsblk
function request_lsblk_format() {
    #требует заданных переменных:
    #LSBLK_FORMAT - формат вывода lsblk по умолчанию
    #LSBLK_FORMATS - массив с форматами вывода lsblk
    #TTY_WIDTH - ширина терминала
    # создаём ассоциативный массив с примерной шириной каждого поля
    declare -A LSBLK_FIELDS_WIDTHS=(
        ["NAME"]=35
        ["TYPE"]=5
        ["FSTYPE"]=12
        ["SIZE"]=8
        ["UUID"]=40
        ["MOUNTPOINTS"]=35
        ["RM"]=3
        ["RO"]=3
        ["ROTA"]=5
    )
    
    # функция для вычисления ширины поля
    function calculate_width_of_lsblk_field() {
        local lsblk_format=$1
        #получаем массив из строки с разделителем - запятая
        local field_names=($(echo "$lsblk_format" | tr ',' '\n'))
        local field_width=0
        for field_name in "${field_names[@]}"; do
            local field_width=$(($field_width + ${LSBLK_FIELDS_WIDTHS[$field_name]}))
        done
        echo $field_width
    }
    # функция для сравнения ширины поля с шириной интерфейса tty для отображения в цвете
    function get_colored_requirement_for_width_of_lsblk_field() {
        local lsblk_format=$1
        local field_width=$(calculate_width_of_lsblk_field "$lsblk_format")
        if [[ "$field_width" -ge "$TTY_WIDTH" ]]; then
            echo -e "${RED}$field_width+${NC}"
        else
            echo -e "${GREEN}$field_width+${NC}"
        fi
    }
    
    echo -e "${BOLD}${YELLOW}Ширина интерфейса tty в символах: ${GREEN}$TTY_WIDTH${NC}"
    echo -e "Пожалуйста, выберите формат вывода lsblk для просмотра списка разделов перед установкой:"
    echo -e "${GREEN}*${NC}) $LSBLK_FORMAT (${YELLOW}по умолчанию, можно просто нажать Enter${NC}; требуется примерно: $(get_colored_requirement_for_width_of_lsblk_field "$LSBLK_FORMAT"))"
    for ((i=0; i<${#LSBLK_FORMATS[@]}; i++)); do
        echo -e "${GREEN}$((i+1))${NC}) ${LSBLK_FORMATS[$i]} (требуется примерно: $(get_colored_requirement_for_width_of_lsblk_field "${LSBLK_FORMATS[$i]}"))"
    done
    echo "при низком разрешении экрана и/или крупном шрифте рекомендуется выбрать короткий формат (например, NAME,TYPE,FSTYPE,SIZE)"
    echo "при FullHD, 4K, 8K и т.п. и относительно мелком шрифте можно отобразить всю необходимую вам информацию по максимуму"
    read -p "Введите номер нужного формата: " format_choice
    
    if [[ "$format_choice" -ge 1 && "$format_choice" -le ${#LSBLK_FORMATS[@]} ]]; then
        export LSBLK_FORMAT="${LSBLK_FORMATS[$((format_choice-1))]}"
    else
        echo -e "${YELLOW}Используется формат по умолчанию:${NC} $LSBLK_FORMAT"
    fi
}
