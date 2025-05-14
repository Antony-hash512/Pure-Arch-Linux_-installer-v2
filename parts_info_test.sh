#!/bin/bash

: << 'TODO'
+ после чистки от говнокода, нужно почистить от коментариев, которые потеряют актуальность
+ отображать в разметке случаи с шифрованием
+ добавить другие параметры для запуска (автовыбор других компонентов и альтернативный xml-файл)
TODO

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
echo -e "${GRAY}${ITALIC}${UNDERLINE}Построение информации...${NC}"

#создаём временные файлы и сохраняем имя в переменные
LSBLK_RAW_INFO=$(mktemp)
LSBLK_RAW_INFO_UPDATED=$(mktemp)
#записываем содержимое во временный файл
#RM или RO - нужно дописать в конец строки чтобы при добавлении дополнительного параметра всё было выровнено по правому краю

#lsblk -o NAME,TYPE,FSTYPE,SIZE,UUID,RM,RO,ROTA > $LSBLK_RAW_INFO
lsblk -o $LSBLK_FORMAT > $LSBLK_RAW_INFO

#расшифровка дальнейшего использования:
#$(echo "$line" | awk '{print $1}') - NAME
#$(echo "$line" | awk '{print $2}') - TYPE
#$(echo "$line" | awk '{print $3}') - FSTYPE
#имеет смысл сделать функции для лучшей читаемости кода
#можно сделать псевдо неймспейс lineop_ для данных групп функций (и отдельный файл lineops.sh)

#определяем длину строки в файле
LENGTH_OF_LINE_IN_LSBLK_RAW_INFO=$(wc -L < $LSBLK_RAW_INFO)

#записываем первую строку с добавочным текстом (если нужен) во второй временный файл
echo "$(head -n 1 $LSBLK_RAW_INFO)" > $LSBLK_RAW_INFO_UPDATED


#проходися по файлу начиная со второй строки в цикле
while IFS= read -r line; do
    #дублируем строку как есть до изменения
    line_orig="$line"
    #заменяем '│ ' на '│·' чтобы избежать ошибочного разбиения на слова
    line=$(echo "$line" | sed 's/│ /│·/g')
    #получаем базовое имя устройства
    device_basename=$(echo "$line" | awk '{print $1}')
    #удаляем любые символы отображающие древовидную структуру из начала строки
    device_basename=$(echo "$device_basename" | sed 's/^[├─└│·]*//')
    #определяем полное имя устройства
    if [[ "$(echo "$line" | awk '{print $2}')" == "lvm" ]]; then
        device_fullname="/dev/mapper/$device_basename"
    elif [[ "$(echo "$line" | awk '{print $2}')" == "part" ]]; then
        device_fullname="/dev/$device_basename"
    elif [[ "$(echo "$line" | awk '{print $2}')" == "crypt" ]]; then
        device_fullname=/dev/mapper/$device_basename
    fi

    if [[ "$(echo "$line" | awk '{print $3}')" == "btrfs" ]]; then
        # Используем функцию для окрашивания слова "btrfs"
        line_colored=$(color_text_in_string "$line_orig" "btrfs" "$CYAN")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED


        #используем функцию get_btrfs_subvolumes
        #если вывод пустой, то выводим сообщение об отсутствии сабволюмов и не делаем дальнейших проверок
        existing_subvolumes_strings=$(get_btrfs_subvolumes "$device_fullname")
        if [[ -z "$existing_subvolumes_strings" ]]; then
            echo -e "${GRAY}${ITALIC}${UNDERLINE}На устройстве $device_fullname нет сабволюмов${NC}" >> $LSBLK_RAW_INFO_UPDATED
 
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
                the_same_flag=0
                for subvolume_with_mount_point in "${!new_btrfs_subvolumes_with_mountpoints[@]}"; do
                    #проверяем, есть ли такой сабволюм в массиве existing_subvolumes
                    for existing_subvolume in "${existing_subvolumes[@]}"; do
                        if [[ "$subvolume_with_mount_point" == "$existing_subvolume" ]]; then
                            the_same_flag=1
                            #окрашиваем в красный
                            new_btrfs_subvolumes_string=$(color_text_in_string "$new_btrfs_subvolumes_string" "$existing_subvolume" "$RED")
                        fi
                    done
                done
                #если the_same_flag равен 1, то выводим сообщение об ошибке
                if [[ "$the_same_flag" == 1 ]]; then
                    echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Сабволюмы которые планируется создать уже существуют на устройстве,\nотредактируйте ${GREEN}${XML_FILE}${NC}${RED} или измените разметку${NC}" >> $LSBLK_RAW_INFO_UPDATED
                    problems["btrfs_subvolume_name_already_exists"]="в файле конфигурации нужно прописать уникальные имена для новых сабволюмов"
                    exit_and_show_problems_flag=1
                elif [[ "$the_same_flag" == 0 ]]; then
                    #окрашиваем в зеленый
                    new_btrfs_subvolumes_string="${GREEN}${new_btrfs_subvolumes_string}${NC}"
                fi
            
                #echo -e "!${BOLD}Планируемые изменения:${NC} ${BLINK}${GREEN}$new_btrfs_subvolumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
                echo -e "!${BOLD}Планируемые изменения:${NC} $new_btrfs_subvolumes_string" >> $LSBLK_RAW_INFO_UPDATED

            fi
        fi
        #удаляем временный ассоциативный массив, если он существует
        if declare -p new_btrfs_subvolumes_with_mountpoints &>/dev/null; then
            unset new_btrfs_subvolumes_with_mountpoints
        fi
    elif [[ "$(echo "$line" | awk '{print $3}')" == "LVM2_member" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "LVM2_member" "$YELLOW")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
        if [[ "$(echo "$line" | awk '{print $2}')" == "crypt" ]]; then
            device_fullname="/dev/mapper/$device_basename"
        else
            device_fullname="/dev/$device_basename"
        fi
        #получаем имя группы томов
        vg_name=$(get_vg_name_for_pv "$device_fullname")
        #если том не принадлежит ни одной группе томов, нет смысла делать дальнейшие проверки
        if [[ -z "$vg_name" ]]; then
            echo -e "!${GRAY}${ITALIC}Не принадлежит ни одной группе томов${NC}" >> $LSBLK_RAW_INFO_UPDATED
        else
            #выводим имя группы томов
            echo -e "!${BOLD}Имя группы томов:${NC} ${YELLOW}$vg_name${NC}" >> $LSBLK_RAW_INFO_UPDATED
            #проверяем точки монтирования из xml-конфига
            new_lvm_volumes_string=$(get_new_lvm_volumes_for_group_with_their_mount_points "$vg_name")
            #получаем массив из строки
            read -r -a new_lvm_volumes <<< "$new_lvm_volumes_string"
            #поучаем список существующий логических томов с преобразованием в одну строку
            existing_lvm_volumes_string=$(one_line "$(safe_lvs --noheading -o lv_name "$vg_name" | tr -d ' ')")
            #получаем массив из строки
            read -r -a existing_lvm_volumes <<< "$existing_lvm_volumes_string"
            #проходимся по массивам для поиска совпадений
            if [[ -n "$new_lvm_volumes_string" ]]; then 
                the_same_flag=0

                for new_lvm_volume in "${new_lvm_volumes[@]}"; do
                    for existing_lvm_volume in "${existing_lvm_volumes[@]}"; do
                        if [[ "$(echo "$new_lvm_volume" | sed 's|->/.*$||' | sed 's|^+||')" == "$existing_lvm_volume" ]]; then
                            echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Том $existing_lvm_volume уже существует на устройстве${NC}" >> $LSBLK_RAW_INFO_UPDATED
                            the_same_flag=1
                            new_lvm_volumes_string=$(color_text_in_string "$new_lvm_volumes_string" "$existing_lvm_volume" "$RED")
                        fi
                    done
                done
                if [[ "$the_same_flag" == 0 ]]; then
                    new_lvm_volumes_string="${GREEN}${new_lvm_volumes_string}${NC}"
                elif [[ "$the_same_flag" == 1 ]]; then
                    problems["lvm_logical_volume_name_already_exists"]="в файле конфигурации нужно прописать уникальные имена для новых томов lvm"
                    exit_and_show_problems_flag=1
                fi

                echo -e "!${BOLD}Планируемые изменения:${NC} ${BLINK}${GREEN}$new_lvm_volumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
            fi
        fi

    elif [[ "$(echo "$line" | awk '{print $3}')" == "ext4" ]]; then
        #окрашиваем находку
        line_colored=$(color_text_in_string "$line_orig" "ext4" "$BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    elif [[ "$(echo "$line" | awk '{print $3}')" == "crypto_LUKS" ]]; then
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
cp $LSBLK_RAW_INFO_UPDATED $LSBLK_RAW_INFO
#выводим содержимое временного файла
cat $LSBLK_RAW_INFO



make_pause





