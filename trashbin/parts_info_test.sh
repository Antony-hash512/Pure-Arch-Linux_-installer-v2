#!/bin/bash


#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mERROR: This script must be run as root\033[0m" >&2
    exit 1
fi

# Подключаем файл с цветовыми переменными
source include/colors.sh # Подключаем функции
source include/main_functions.sh
source include/shared_functions.sh
trap 'cleanup_all' EXIT


# Заранее вычисленные степени 1024
export MB=1048576  # 1024^2
export GB=1073741824  # 1024^3
export TB=1099511627776  # 1024^4
export PB=1125899906842624  # 1024^5
export EB=1152921504606846976  # 1024^6

# Строковые константы
export AUTODIR="autocreated_scripts"
export XML_FILE="components.xml"
export XML_PARSER="get_data_from_components_xml.py"
export CHROOT_SCRIPT="run_inside_chroot.sh"

# Формат вывода lsblk по умолчанию
export LSBLK_FORMAT="NAME,TYPE,FSTYPE,SIZE,UUID,RM,RO,ROTA"
TTY_WIDTH=$(tput cols)

# Создаем массив с возможными вариантами
declare -a LSBLK_FORMATS=(
    "NAME,TYPE,FSTYPE,SIZE,UUID,MOUNTPOINTS,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,UUID,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,UUID,MOUNTPOINTS"
    "NAME,TYPE,FSTYPE,SIZE,UUID"
    "NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS"
    "NAME,TYPE,FSTYPE,SIZE"
    "NAME,TYPE,FSTYPE"
    "NAME,TYPE,FSTYPE,UUID"
)

request_lsblk_format

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


# Обработка аргументов командной строки
INSTALL_LOCATION_ID=""
while getopts "i:" opt; do
  case $opt in
    i)
      # Проверяем существует ли указанное значение install_location
      if check_install_location_exists "$OPTARG"; then
        INSTALL_LOCATION_ID="$OPTARG"
        echo -e "${GREEN}Используем указанное место установки: $INSTALL_LOCATION_ID${NC}"
      else
        echo -e "${RED}Указанное место установки '$OPTARG' не найдено${NC}"
      fi
      ;;
    \?)
      echo -e "${RED}Неверный параметр -$OPTARG${NC}" >&2
      ;;
  esac
done

# Если INSTALL_LOCATION_ID не был задан через ключ -i или указанное значение не найдено
if [[ -z "$INSTALL_LOCATION_ID" ]]; then
    # Выбор места установки
    INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID места установки")
fi

#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить имена открытых крипто-контейнеров
declare -A OPENED_CRYPT_CONTAINERS


#echo -e "${CYAN}Общая информация:${NC}"
#echo -e "${YELLOW}список разделов до начала установки:${NC}"
#lsblk -o $LSBLK_FORMAT
#make_pause

#получаем информацию содержащуюся в xml-файле
NEW_MOUNTPOINTS_AMOUNT=$(parse_xml "install_location" "get_amount_of_new_mountpoints")
echo -e "${YELLOW}Количество новых точек монтирования:${NC} $NEW_MOUNTPOINTS_AMOUNT"

#создаём массив для хранения имен новых точек монтирования
declare -a NEW_MOUNTPOINTS

for ((i=0; i<$NEW_MOUNTPOINTS_AMOUNT; i++)); do
    NEW_MOUNTPOINT=$(parse_xml "install_location" "get_new_mountpoint" "$i")
    CURRENT_POINT_NAME="new_point$i"
    declare -A "$CURRENT_POINT_NAME"
    #получаем ассоциативный массив из строки
    eval "$CURRENT_POINT_NAME=$NEW_MOUNTPOINT"
    NEW_MOUNTPOINTS+=("$CURRENT_POINT_NAME")
done

# вывод полученной из xml-файла информации на экран и открытие крипто-контейнеров luks
for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    crypt_mode=${current_row["crypt_mode"]}
    echo -e "${YELLOW}Точка монтирования $row:${NC} $mount_point $type $crypt_mode"
    echo "Тип монтирования: $type"

    # Определяем устройство из нового формата XML
    if [[ -n "${current_row["lv-volume"]}" ]]; then
        device_name=${current_row["lv-volume"]}
    #elif [[ -n "${current_row["pv-volume"]}" ]]; then
    #    device_name=${current_row["pv-volume"]}
    #не используемся, в этой версии файла не тестируются случаи с шифрованием
    elif [[ -n "${current_row["uuid"]}" ]]; then
        device_name=$(check_uuid_exists "${current_row["uuid"]}") || {
            echo -e "${RED}Устройство с UUID ${current_row["uuid"]} не найдено${NC}" >&2
            continue
        }
    else
        echo -e "${RED}Не удалось определить устройство для точки монтирования $row${NC}" >&2
        continue
    fi
    echo -e "${GREEN}Имя устройства: $device_name${NC}"
    current_row["device_name"]=$device_name

    # Заполняем device_for_operations только для томов без шифрования
    current_row["device_for_operations"]=$device_name


    # Открытие крипто-контейнера для зашифрованных томов
    if [[ "$crypt_mode" == *"pwd"* ]]; then
        echo -e "${YELLOW}${ITALIC}Открытие крипто-контейнера luks с паролем${NC}"
        open_crypt_container_by_pwd "$device_name"
    elif [[ "$crypt_mode" == *"file"* ]]; then
        echo -e "${YELLOW}${ITALIC}Открытие крипто-контейнера luks с файлом-ключом${NC}"
        key_file=$(parse_xml "install_location" "get_key_file" "$row")
        open_crypt_container_by_file "$device_name" "$key_file"
    fi
done

# V отсуда будем переность инфу в новый файл

echo -e "${CYAN}Информация о вносимых изменениях:${NC}"
echo -e "${GRAY}Построение информации...${NC}"

#создаём временные файлы и сохраняем имя в переменные
LSBLK_RAW_INFO=$(mktemp)
LSBLK_RAW_INFO_UPDATED=$(mktemp)
#записываем содержимое во временный файл
lsblk -o $LSBLK_FORMAT > $LSBLK_RAW_INFO


#записываем первую строку с добавочным текстом (если нужен) во второй временный файл
echo "$(head -n 1 $LSBLK_RAW_INFO)" > $LSBLK_RAW_INFO_UPDATED


#проходися по файлу начиная со второй строки в цикле
while IFS= read -r line; do
    #дублируем строку как есть до изменения
    line_orig="$line"
    #заменяем '│ ' на '│·' чтобы избежать ошибочного разбиения на слова
    line=$(echo "$line" | sed 's/│ /│·/g')
    #получаем базовое имя устройства
    #удаляем любые символы отображающие древовидную структуру из начала строки
    device_basename=$(echo "$line" | awk '{print $1}' | sed 's/^[├─└│·]*//')
    type_from_lsblk=$(echo "$line" | awk '{print $2}')
    fstype_from_lsblk=$(echo "$line" | awk '{print $3}')
    #определяем полное имя устройства
    if [[ "$type_from_lsblk" == "lvm" ]]; then
        device_fullname="/dev/mapper/$device_basename"
    elif [[ "$type_from_lsblk" == "part" ]]; then
        device_fullname="/dev/$device_basename"
    elif [[ "$type_from_lsblk" == "crypt" ]]; then
        device_fullname=/dev/mapper/$device_basename
    fi

    if [[ "$fstype_from_lsblk" == "btrfs" ]]; then
        # Используем функцию для окрашивания слова "btrfs"
        line_colored=$(color_text_in_string "$line_orig" "btrfs" "$CYAN")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED


        #используем функцию get_btrfs_subvolumes
        #если вывод пустой, то выводим сообщение об отсутствии сабволюмов и не делаем дальнейших проверок
        existing_subvolumes_strings=$(get_btrfs_subvolumes "$device_fullname")
        if [[ -z "$existing_subvolumes_strings" ]]; then
            echo -e "${GRAY}На устройстве $device_fullname нет сабволюмов${NC}" >> $LSBLK_RAW_INFO_UPDATED
 
            #для начала создаём ассоциативный массив (в текущей реализации временный
            #т.к. будет пересоздаваться при каждой итерации цикла)
            declare -A new_btrfs_subvolumes_with_mountpoints
            #заполняем массив
            #нужно передавать имя массива, а не его содержимое
            fill_in_array_by_new_btrfs_subvolumes_for_device "$device_fullname" new_btrfs_subvolumes_with_mountpoints

            #формируем строку с планируемыми изменениями
            new_btrfs_subvolumes_string=$(get_string_for_new_btrfs_subvolumes_for_device new_btrfs_subvolumes_with_mountpoints)
            #если полученная строка не пустая то выводим сообщение о планируемых изменениях
            if [[ -n "$new_btrfs_subvolumes_string" ]]; then 
                echo -e "!${BOLD}Планируемые изменения:${NC} ${GREEN}$new_btrfs_subvolumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
            fi
        else
            #получаем список существующих сабволюмов в формате в одну строку
            existing_subvolumes_string=$(one_line "$existing_subvolumes_strings")
            #получаем массив из строки
            read -r -a existing_subvolumes <<< "$existing_subvolumes_string"
            #выводим список сабволюмов на экран
            echo -e "!${BOLD}Имеющиеся сабволюмы:${NC} ${CYAN}$existing_subvolumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
            
            #для начала создаём ассоциативный массив (в текущей реализации временный
            #т.к. будет пересоздаваться при каждой итерации цикла)
            declare -A new_btrfs_subvolumes_with_mountpoints
            #заполняем массив
            #нужно передавать имя массива, а не его содержимое
            fill_in_array_by_new_btrfs_subvolumes_for_device "$device_fullname" new_btrfs_subvolumes_with_mountpoints

            #формируем строку с планируемыми изменениями
            new_btrfs_subvolumes_string=$(get_string_for_new_btrfs_subvolumes_for_device new_btrfs_subvolumes_with_mountpoints)
            #если ассоциативный массив не пустой, то проверяем, есть ли в ней уже существующие сабволюмы
            if [[ -n "$new_btrfs_subvolumes_string" ]]; then 
                is_unique_flag=0
                for subvolume_with_mount_point in "${!new_btrfs_subvolumes_with_mountpoints[@]}"; do
                    #проверяем, есть ли такой сабволюм в массиве existing_subvolumes
                    for existing_subvolume in "${existing_subvolumes[@]}"; do
                        if [[ "$subvolume_with_mount_point" == "$existing_subvolume" ]]; then
                            is_unique_flag=1
                            #окрашиваем в красный
                            new_btrfs_subvolumes_string=$(color_text_in_string "$new_btrfs_subvolumes_string" "$existing_subvolume" "$RED")
                        fi
                    done
                done
                #если the_same_flag равен 1, то выводим сообщение об ошибке
                if (( is_unique_flag == 0 )); then
                    #окрашиваем в зеленый
                    new_btrfs_subvolumes_string="${GREEN}${new_btrfs_subvolumes_string}${NC}"
                else
                    echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Сабволюмы которые планируется создать уже существуют на устройстве,\nотредактируйте ${GREEN}${XML_FILE}${NC}${RED} или измените разметку${NC}" >> $LSBLK_RAW_INFO_UPDATED
                    problems["btrfs_subvolume_name_already_exists"]="в файле конфигурации нужно прописать уникальные имена для новых сабволюмов"
                    exit_and_show_problems_flag=1    
                fi
                    echo -e "!${BOLD}Планируемые изменения:${NC} $new_btrfs_subvolumes_string" >> $LSBLK_RAW_INFO_UPDATED

            fi
        fi
        #удаляем временный ассоциативный массив, если он существует
        if declare -p new_btrfs_subvolumes_with_mountpoints &>/dev/null; then
            unset new_btrfs_subvolumes_with_mountpoints
        fi
    elif [[ "$fstype_from_lsblk" == "LVM2_member" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "LVM2_member" "$YELLOW")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
        if [[ "$type_from_lsblk" == "crypt" ]]; then
            device_fullname="/dev/mapper/$device_basename"
        else
            device_fullname="/dev/$device_basename"
        fi
        #получаем имя группы томов
        vg_name=$(get_vg_name_for_pv "$device_fullname")
        #если том не принадлежит ни одной группе томов, нет смысла делать дальнейшие проверки
        if [[ -z "$vg_name" ]]; then
            echo -e "!${GRAY}Не принадлежит ни одной группе томов${NC}" >> $LSBLK_RAW_INFO_UPDATED
        else
            #выводим имя группы томов
            echo -e "!${BOLD}Имя группы томов:${NC} ${YELLOW}$vg_name${NC}" >> $LSBLK_RAW_INFO_UPDATED

            #создаём временный ассоциативный массив для хранения новых томов lvm
            declare -A new_lvm_volumes
            declare -A new_lvm_volumes_is_luks
            #заполняем массив
            fill_in_array_by_new_lvm_volumes_for_group "$vg_name" new_lvm_volumes new_lvm_volumes_is_luks
            #формируем строку с планируемыми изменениями
            new_lvm_volumes_string=$(get_string_for_new_lvm_volumes_for_group new_lvm_volumes new_lvm_volumes_is_luks)
           
            #поучаем список существующий логических томов с преобразованием в одну строку
            existing_lvm_volumes_string=$(one_line "$(safe_lvs --noheading -o lv_name "$vg_name" | tr -d ' ')")
            #получаем массив из строки
            read -r -a existing_lvm_volumes <<< "$existing_lvm_volumes_string"
            #проходимся по массивам для поиска совпадений
            if [[ -n "$new_lvm_volumes_string" ]]; then 
                is_unique_flag=0

                for new_lvm_volume in "${!new_lvm_volumes[@]}"; do
                    for existing_lvm_volume in "${existing_lvm_volumes[@]}"; do
                        if [[ "$new_lvm_volume" == "$existing_lvm_volume" ]]; then
                            echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Том $existing_lvm_volume уже существует на устройстве${NC}" >> $LSBLK_RAW_INFO_UPDATED
                            is_unique_flag=1
                            new_lvm_volumes_string=$(color_text_in_string "$new_lvm_volumes_string" "$existing_lvm_volume" "$RED")
                        fi
                    done
                done
                if (( is_unique_flag == 0 )); then
                    new_lvm_volumes_string="${GREEN}${new_lvm_volumes_string}${NC}"
                else
                    problems["lvm_logical_volume_name_already_exists"]="в файле конфигурации нужно прописать уникальные имена для новых томов lvm"
                    exit_and_show_problems_flag=1
                fi

                echo -e "!${BOLD}Планируемые изменения:${NC} $new_lvm_volumes_string" >> $LSBLK_RAW_INFO_UPDATED
            fi
        fi
        #удаляем временные ассоциативные массивы, если они существуют
        if declare -p new_lvm_volumes &>/dev/null; then
            unset new_lvm_volumes
        fi
        if declare -p new_lvm_volumes_is_luks &>/dev/null; then
            unset new_lvm_volumes_is_luks
        fi

    elif [[ "$fstype_from_lsblk" == "ext4" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "ext4" "$BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    elif [[ "$fstype_from_lsblk" == "crypto_LUKS" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "crypto_LUKS" "$LIGHT_BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    else
        #пишем строку как есть
        echo "$line_orig" >> $LSBLK_RAW_INFO_UPDATED
    fi
    #т.к. в ext4 можно форматнуть любой раздел, эту проверку осуществляем вне предыдущего if
    #проверяем, есть ли такой раздел в массиве NEW_MOUNTPOINTS
    
    #проверяем отмечен ли для форматирования через функцию check_ext4_partitions_to_format_with_their_mount_points
    string_checker=$(check_ext4_partitions_to_format_with_their_mount_points "$device_fullname")
    if [[ -n "$string_checker" ]]; then
        echo -e "!${BOLD}Планируемые изменения:${NC} ${RED}$string_checker${NC}" >> $LSBLK_RAW_INFO_UPDATED
        echo -e "!${RED}Перед тем как продолжить, проверьте что на устройстве нет важных данных${NC}" >> $LSBLK_RAW_INFO_UPDATED
        echo -e "!${YELLOW}Если хотите прервать выполнение скрипта для перепроверки, нажмите ctrl+c${NC}" >> $LSBLK_RAW_INFO_UPDATED
    fi
done < <(sed '1d' $LSBLK_RAW_INFO)

# Обновляем первый временный файл и обнуляем второй
mv $LSBLK_RAW_INFO_UPDATED $LSBLK_RAW_INFO
#выводим содержимое временного файла
cat $LSBLK_RAW_INFO



make_pause





