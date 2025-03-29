for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}

     # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    crypt_mode=${current_row["crypt_mode"]}

    echo -e "${YELLOW}Точка монтирования $row:${NC} $mount_point $type $crypt_mode $name"
    echo "Тип монтирования: $type"

    #в каждый кейс прописан подкейс с опциями шифрования
    #заполняем случаи none_in_none и none
    case "$type" in
        "format_ext4")
            #в данном случае задан только партишн, который будет форматироваться
            ext4_path=${current_row["name"]}
            case "$crypt_mode" in
                "none")
                    :
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs")
            #в данном случае заданы подтом, который будет создаваться, и существующий партишн, вне lvm
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            case "$crypt_mode" in
                "none")
                    :
                    ;;
                "file")
                    :
                    ;;
                "pwd")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs_in_lvm")
            #этот случай польностью протестирован (в режиме none_in_none)
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже          
            case "$crypt_mode" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[2]}"
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[2]}"
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            
            ;;
        "new_ext4_in_lvm")
            lv_name="${names[0]}"
            #имя и группы нужно будет получить через спец. функции, которые работают через регексы и учитывают запись через mapper
            #vg_name=$(echo "$lv_name" | awk -F/ '{print $3}')  # Получаем имя группы томов
            case "$crypt_mode" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[1]}"
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[1]}"
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                *)
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Неизвестный тип: $type" >&2
            exit 1
            ;;
    esac
    

    #на этом этап открываем крипто-контейнеры luks, если это требуется
    #находим имя устройства
    if [[ "$type" == *"btrfs"* ]]; then
        device_name=${names[1]}
    elif [[ "$type" == *"ext4"* ]]; then
        device_name=${names[0]}
    fi
    echo -e "${GREEN}Имя устройства: $device_name${NC}"
    current_row["device_name"]=$device_name
    #если в строке crypt_mode содержится подстрока pwd или file, то открываем крипто-контейнер
    if [[ "$crypt_mode" == *"pwd"* || "$crypt_mode" == *"file"* ]]; then
        echo -e "${YELLOW}${ITALIC}Открытие крипто-контейнера luks${NC}"
        #создаём имя для открытого крипто-контейнера
        opened_crypt_container_name="opened_luks_$(basename "$device_name")_$(date +%s_%N)_$RANDOM"
        #открываем крипто-контейнер
        open_crypt_container_by_pwd "$device_name" "$opened_crypt_container_name"
    fi
done
