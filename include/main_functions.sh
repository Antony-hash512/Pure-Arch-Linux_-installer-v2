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

    # Деактивируем LVM-группы и тома, связанные с открытыми крипто-контейнерами
    for device in "${!OPENED_CRYPT_CONTAINERS[@]}"; do
        mapper_name=${OPENED_CRYPT_CONTAINERS[$device]}
        mapper_path="/dev/mapper/$mapper_name"
        vg_names=$(safe_pvs "$mapper_path" --noheadings -o vg_name 2>/dev/null | tr -d ' ')
        if [ -n "$vg_names" ]; then
            for vg in $vg_names; do
                echo -e "${GRAY}Деактивируем VG $vg для $mapper_path${NC}"
                vgchange -an "$vg" || echo -e "${YELLOW}Не удалось деактивировать VG $vg${NC}"
            done
        fi
    done

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

#Функция для закрытия дескрипторов (не используется)
close_descriptors() {
    # узнали максимальное число дескрипторов для процесса
    max=$(ulimit -n)
    for ((fd=3; fd<max; fd++)); do
        # закроем дескриптор, ошибки проигнорируем
        exec {fd}>&- 2>/dev/null
    done
}


#Функция для активации LVM-групп, относящихся к открытым крипто-контейнерам
activate_lvm_groups_for_opened_crypt_containers() {
    local vg_name=$1
    #close_descriptors
    export LVM_SUPPRESS_FD_WARNINGS=1

    if [ -n "$vg_name" ]; then
        # путь /dev/<vg_name> существует только для активной группы
        if [ ! -e "/dev/$vg_name" ]; then
            echo -e "${GRAY}Активируем VG $vg_name${NC}"
            vgchange -ay "$vg_name" || echo -e "${YELLOW}Не удалось активировать VG $vg_name${NC}"
        else
            echo -e "${GRAY}VG $vg_name уже активна${NC}"
        fi

        # активируем логические тома группы
        local lv_names
        lv_names=$(safe_lvs --noheadings -o lv_name "$vg_name" 2>/dev/null | tr -d ' ')
        if [ -n "$lv_names" ]; then
            for lv in $lv_names; do
                if [ ! -e "/dev/$vg_name/$lv" ]; then
                    echo -e "${GRAY}Активируем LV $vg_name/$lv${NC}"
                    lvchange -ay "$vg_name/$lv" || echo -e "${YELLOW}Не удалось активировать LV $vg_name/$lv${NC}"
                else
                    echo -e "${GRAY}LV $vg_name/$lv уже активен${NC}"
                fi
            done
        fi
    fi
    # Снимаем переменную окружения
    unset LVM_SUPPRESS_FD_WARNINGS
}

#Функция для вывода логотипа
show_logo() {
    echo -e "$LOGO"
}

#Функция для проверки существования указанного id в xml файле
check_xml_id_exists() {
    local component_type="$1"
    local id="$2"
    # Напрямую вызываем парсер, так как переданный ID не является текущим INSTALL_LOCATION_ID
    if [[ -n "$(python3 $XML_PARSER "$component_type" "$id" check_id_exists 2>/dev/null)" ]]; then
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

#Функция для проверки ключа и запроса у пользователя, если ключ не был передан
check_key_and_request_component_id() {
    local component_type="$1"
    local key
    local current_value
    local prompt_text

    case "$component_type" in
        "install_location")
            key="i"
            current_value="$INSTALL_LOCATION_ID"
            prompt_text="Введите ID установки"
            ;;
        "softpack")
            key="s"
            current_value="$SOFTPACK_ID"
            prompt_text="Введите ID набора софта"
            ;;
        "driverspack")
            key="d"
            current_value="$DRIVERS_ID"
            prompt_text="Введите ID набора драйверов"
            ;;
        "settings")
            key="o"
            current_value="$SETTINGS_ID"
            prompt_text="Введите ID настроек"
            ;;
        *)
            echo -e "${RED}Неизвестный тип компонента: $component_type${NC}" >&2
            exit 1
            ;;
    esac

    if [[ -z "$current_value" ]]; then
        # Выбор места установки
        current_value=$(request_component_id "$component_type" "$prompt_text")
    else
        # если уже задан значит было получено из ключа -i
        # проверяем существует ли указанное место установки
        if ! check_xml_id_exists "$component_type" "$current_value"; then
            echo -e "${RED}Указанное через ключ -$key место установки '$current_value' не найдено в файле ${GREEN}$XML_FILE${NC}" >&2
            exit 1
        fi
        echo -e "${GREEN}Используем указанное место установки из ключа -$key: $current_value${NC}" > /dev/tty
    fi
    # возвращаем значение (в процедурном стиле, для удобства использования,
    # чтобы не было необходимости прописывать эти id'шники при вызове)
    case "$component_type" in
        "install_location")
            INSTALL_LOCATION_ID="$current_value"
            ;;
        "softpack")
            SOFTPACK_ID="$current_value"
            ;;
        "driverspack")
            DRIVERS_ID="$current_value"
            ;;
        "settings")
            SETTINGS_ID="$current_value"
            ;;
    esac
}


#Функция для добавления проблемы в массив problems
add_problem() {
     local key=$1 msg=$2
     problems["$key"]+="$msg\n"
     EXIT_AND_SHOW_PROBLEMS_FLAG=1
}


#Функция для перевода в байты
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
    #local free_space=$(safe_vgs "$vg_name" --noheadings --nosuffix --units b | grep VFree | awk '{print $2}')
    local free_space=$(vgs "$vg_name" --noheadings --nosuffix --units b -o vg_free | tr -d '[:space:]')
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
#используем трюк с дополнительной функцией, для "бегства" из подпроцесса (сабшелла)
get_btrfs_mountpoint() {
    local btrfs_device=$1
    local btrfs_mountpoint=""
    add_btrfs_mountpoint_to_array "$btrfs_device"
    echo "${ALL_BTRFS_MOUNTPOINTS[$btrfs_device]}"
}

add_btrfs_mountpoint_to_array() {
    local btrfs_device=$1 #требуется указать полный путь к устройству
    local btrfs_mountpoint=""
    # проверяем, что устройство btrfs является логическим томом LVM, а не в основной разметке диска и не в luks
    if safe_lvs "$btrfs_device" &>/dev/null; then
        #стандартизируем путь к устройству
        btrfs_device=$(standardize_lvm_format "$btrfs_device")
    fi

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
        ALL_BTRFS_MOUNTPOINTS["$btrfs_device"]="$btrfs_mountpoint"
    fi
    #echo "$btrfs_mountpoint"
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

#Функция для заполнения массива pv_devices на основе данных из от uuids из xml-файла
fill_in_array_by_pv_devices() {
    local -a pv_uuids
    local pv_uuids_string=$1
    local -n pv_devices_ref=$2
    local flag_of_not_found_devices=false
    
    #удаляем пробелы в строке, табуляции, переносы строк и возвраты каретки
    pv_uuids_string=$(echo "$pv_uuids_string" | tr -d '\r\n\t ')
    #удаляем запятую в конце строки, если после неё ничего нет
    pv_uuids_string=$(echo "$pv_uuids_string" | sed 's/,$//')

    IFS=',' read -r -a pv_uuids <<< "$pv_uuids_string"

    #проверяем наличие хотя бы одного uuid
    if [ ${#pv_uuids[@]} -eq 0 ]; then
        echo -e "${RED}Не найдены uuid физических томов lvm${NC}" >&2
        add_problem "syntax_problem_in_xml_file" "Не удалось спарсить хотя бы один uuid'шник luks c pv lvm. Они правильно прописаны в xml?"
        return 1
    fi

    for pv_uuid in "${pv_uuids[@]}"; do
        if ! pv_device=$(check_uuid_exists "$pv_uuid"); then
            echo -e "${RED}Устройство с uuid '$pv_uuid' не существует${NC}" >&2
            flag_of_not_found_devices=true
            add_problem "partition_device_by_uuid_not_found" "Ошибка устройство с uuid $pv_uuid не найдено"
        else
            pv_devices_ref+=("$pv_device")
        fi
    done

    if [[ "$flag_of_not_found_devices" == true ]]; then
        return 1
    else
        return 0
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

            # для Btrfs-субтомов в LVM стандартизируем оба пути
            #эта функция вызывается для для строк в которых найдено "btrfs"
            #luks'ы для которых не предназначена standardize_lvm_format сюда не попадут
            if [[ "$type" == "new_subvol_in_btrfs_in_lvm" ]]; then
                current_check_device=$(standardize_lvm_format "$current_check_device")
                current_device_from_input_form=$(standardize_lvm_format "$device_from_input")
            else
                # для остальных случаев (чистый Btrfs) сравниваем как есть
                current_device_from_input_form=$device_from_input
            fi

            #если имя устройства совпадает с именем устройства в из xml-файла, то добавляем в ассоциативный массив
            if [[ "$current_device_from_input_form" == "$current_check_device" ]]; then
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
safe_pvs_test() {
    close_descriptors
    pvs "$@"
    local ret_val=$?
    return $ret_val
}

# Безопасный вызов lvs без утечек дескрипторов
safe_lvs_test() {
    close_descriptors
    lvs "$@"
    local ret_val=$?
    return $ret_val
}

#Безопасный вызов vgs без утечек дескрипторов
safe_vgs_test(){
    close_descriptors
    vgs "$@"
    local ret_val=$?
    return $ret_val
}



# Вызов pvs без утечек дескрипторов
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

# Вызов lvs без утечек дескрипторов
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

#Вызов vgs без утечек дескрипторов
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
    current_row["luks_device_fullname"]="$device_name"
    
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

    ask_user_action_with_array "$prompt" "opt_array" "$default_action"
}

# Функция для выбора действия пользователем с массивом вариантов
ask_user_action_with_array() {
    local prompt="$1"      # Текст приглашения
    local -n opt_array="$2"  # ссылка на массив вариантов
    local default_action="$3"  # Действие по умолчанию при некорректном вводе
    local num_options=${#opt_array[@]} # количество вариантов

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
    local bname=$(basename "$device_name")
    local map_name=$(lsblk -l -n -o NAME,TYPE,PKNAME | awk -v dev="$bname" '$2=="crypt" && $3==dev {print $1; exit}')
    if [[ -n "$map_name" ]]; then
        echo -e "${YELLOW}${BOLD}Крипто-контейнер для ${GREEN}$device_name${YELLOW} уже открыт в системе как ${GREEN}$map_name${NC}, пропускаем открытие${NC}" > /dev/tty
        #OPENED_CRYPT_CONTAINERS["$device_name"]="$map_name" уже и так сохранятеся в функции save_crypt_container_info
        save_crypt_container_info "$device_name" "$map_name"
        return 0
    else
        return 1
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
        #echo -e "${YELLOW}Попытка $attempts из $max_attempts. Введите пароль для контейнера $device_name${NC}"
        echo -e "${YELLOW}Введите пароль для контейнера $device_name${NC}"
            
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
        #echo -e "${YELLOW}Попытка $attempts из $max_attempts. Открываем контейнер $device_name с помощью файла-ключа...${NC}"
        echo -e "${YELLOW}Открываем контейнер $device_name с помощью файла-ключа...${NC}"
        
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
    if [[ "$EXIT_AND_SHOW_PROBLEMS_FLAG" == 1 ]]; then
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

# Функция для проверки существования физического тома lvm
check_device_is_pv() {
    local device_name=$1
    if safe_pvs "$device_name" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Функция для проверки физического тома lvm в группе томов
check_pv_in_vg() {
    local device_name=$1
    local vg_name=$2
    local pv_vg
    if ! pv_vg=$(safe_pvs --noheadings -o vg_name "$device_name" 2>/dev/null | tr -d ' '); then
        return 1
    fi
    if [[ "$pv_vg" == "$vg_name" ]]; then
        return 0
    else
        return 1
    fi
}

# Процедура для открытия всех luks-контейнеров c pv lvm,
# полученных из прописанных uuidшников в xml-файле
# Включает себя действия, которые дублируются 
# в обоих случаях *_in_lvm для crypt_mode = none_in_*
open_all_luks_devices(){
    #требует заданных переменных:
    #OPENED_CRYPT_CONTAINERS - массив с открытыми luks-контейнерами
    #luks_devices - массив с устройствами, которые нужно открыть
    #vg_name - имя группы томов
    #crypt_mode - режим открытия luks-контейнеров
    #current_row - текущая значения в цикле точек монтирования
    
    #если все устройства существуют, то открываем крипто-контейнеры
    for luks_device in "${luks_devices[@]}"; do
        if [[ "$crypt_mode" == "none_in_file" ]]; then
            #получаем путь к файлу-ключу
            keyfile=${current_row["keyfile"]}
            #используем функцию для открытия крипто-контейнера
            open_crypt_container_by_file "$luks_device" "$keyfile"
        elif [[ "$crypt_mode" == "none_in_pwd" ]]; then
            open_crypt_container_by_pwd "$luks_device"
        fi
        #получаем имя физического тома из ассоциативного массива OPENED_CRYPT_CONTAINERS
        #(был добавлен при выполнении одной из предыдущих функций)
        pv_device="/dev/mapper/${OPENED_CRYPT_CONTAINERS["$luks_device"]}"
        #проверяем является ли это физическим томом lvm
        if ! check_device_is_pv "$pv_device"; then
            #пишем предупреждение:
            echo -e "${RED}Открытое устройство '$pv_device' не является физическим томом lvm${NC}" >&2
            echo -e "${RED}Рекомендуется перепроверить данные в xml-файле ${YELLOW}(ctrl+c для выхода)${NC}" >&2
            #не выходим автоматически т.к. это просто лишний открытый крипто-контейнер, не критично
            make_pause
        else
            #проверяем в правильную ли группу томов он входит
            if ! check_pv_in_vg "$pv_device" "$vg_name"; then
                echo -e "${RED}Физический том '$pv_device' не входит в группу томов '$vg_name'${NC}" >&2
                echo -e "${RED}Рекомендуется перепроверить данные в xml-файле ${YELLOW}(ctrl+c для выхода)${NC}" >&2
                #не выходим автоматически т.к. это просто лишний открытый крипто-контейнер, не критично
                make_pause
            fi
        fi 
    done
    # Активируем LVM-группу
    activate_lvm_groups_for_opened_crypt_containers "$vg_name"
    # Предупреждаем пользователя о подводном камне
    echo -e "${YELLOW}ВНИМАНИЕ: в таком режиме используйте только зашифрованные физические тома lvm для данной группы томов иначе будет дыра в безопасности;${NC}"
                
}

configure_crypt_volumes_by_ref(){
    local -n current_row=$1
    local luks_device_fullname=${current_row["luks_device_fullname"]}
    local crypt_mode=${current_row["crypt_mode"]}
    local mount_point=${current_row["mount_point"]}
    local type=${current_row["type"]}
    function get_mapper_name(){
        local crypt_uuid=$1
        echo "crypt_${crypt_uuid//-/_}"
    }

    #декларируем массив uuids
    declare -a uuids

    if [[ "$type" == *"_in_lvm"* && "$crypt_mode" == *"none_in_"* ]]; then
        pv_uuids_string=${current_row["pv-volumes-uuids"]}
        uuids=($(echo "$pv_uuids_string" | tr ',' '\n'))
    else
        uuids=("$(blkid -s UUID -o value "$luks_device_fullname")")
    fi
    for uuid in "${uuids[@]}"; do
        if [[ $crypt_mode == *"pwd"* ]]; then
           echo "$(get_mapper_name "$uuid") UUID=$uuid none luks" >> $INST_DIR/etc/crypttab
        elif [[ $crypt_mode == *"file"* ]]; then
            echo "$(get_mapper_name "$uuid") UUID=$uuid ${current_row["keyfile"]} luks" >> $INST_DIR/etc/crypttab
        fi  
    done

    if [[ "$mount_point" == "/" ]]; then
        echo "GRUB_CMDLINE_LINUX=\"\\" >> $INST_DIR/etc/default/grub
        for uuid in "${uuids[@]}"; do   
            echo "  cryptdevice=UUID=$uuid:$(get_mapper_name "$uuid")\\" >> $INST_DIR/etc/default/grub
        done
        if [[ "$type" == *"_in_lvm"* && "$crypt_mode" == *"none_in_"* ]]; then
            echo "  root=${current_row["lv-volume"]}" >> $INST_DIR/etc/default/grub
        else
            echo "  root=/dev/mapper/$(get_mapper_name "${uuids[0]}")" >> $INST_DIR/etc/default/grub
        fi
        if [[ $type == *"btrfs"* ]]; then
            echo "  rootflags=subvol=${current_row["subvolume"]}\\" >> $INST_DIR/etc/default/grub
        fi
        echo "\"" >> $INST_DIR/etc/default/grub
    fi
}

#Функция для настройки зашифрованных разделов по uuid
# configure_crypt_volumes_by_uuid(){
#    local crypt_uuid=$1
#    local keyfile=$2
#    # Генерируем уникальное имя контейнера на основе UUID
#    local uuid_name=${crypt_uuid//-/_}
#    local mapper_name="crypt_${uuid_name}"
#    if [[ -z "$keyfile" ]]; then
#        echo "$mapper_name UUID=$crypt_uuid none luks" >> $INST_DIR/etc/crypttab
#    else
#        echo "$mapper_name UUID=$crypt_uuid $keyfile luks" >> $INST_DIR/etc/crypttab
#    fi
#    echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$crypt_uuid:$mapper_name root=/dev/mapper/$mapper_name\"" >> $INST_DIR/etc/default/grub
#}
#
##Функция для настройки зашифрованных разделов по полному имени устройства
#configure_crypt_volumes_by_device_fullname(){
#    local crypt_fullname=$1
#    local keyfile=$2
#    local crypt_uuid=$(blkid -s UUID -o value "$crypt_fullname")
#    if [[ -z "$keyfile" ]]; then
#        configure_crypt_volumes_by_uuid "$crypt_uuid"
#    else
#        configure_crypt_volumes_by_uuid "$crypt_uuid" "$keyfile"
#    fi
#}