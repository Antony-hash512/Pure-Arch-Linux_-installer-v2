#открываем крипто-контейнеры luks, чтобы потом отобразить результат
# TODO: нужно реализовать функционал по откладыванию на потом создания крипто-контейнеров, 
#       но при этом отобразить для пользователя все запланированные изменения
# текущие решение: записываем в поле current_row["device_for_operations"] "i'm not ready yet"
# потом можно будет проверить, если в этом поле записано "i'm not ready yet", и завершить запланированные операции

# ассоциативный массив, который хранит строки с описанием запланированных изменений
declare -A pending_commands_description
#будет использоваться в качестве ключа результат возврата функции get_device_basename4lsblk
#чтобы легко было найти в выхлопе lsblk и отобразить для пользователя все запланированные изменения

for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получает короткие алиасы переменных и xml-файла
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
    #устройства с которыми будут проводиться операции будет внесено в поле current_row["device_for_operations"]
    #это может быть открытый luks или продублированное имя устройства, если шифрование не используется
    #для btrfs название сабволюма будет внесено в поле current_row["subvolume"] для удобства

    case "$type" in
        "format_ext4")
            #в данном случае задан только партишн, который будет форматироваться
            ext4_partition=${current_row["name"]}
            basename_of_ext4_partition=$(get_device_basename4lsblk "$ext4_partition")
            case "$crypt_mode" in
                "none")
                    current_row["device_for_operations"]=$ext4_partition
                    ;;
                "file")
                    #получаем путь к файлу-ключу
                    #keyfile=${current_row["keyfile"]}
                    # пояснение: данные операции здесь закомментированы, т.к. их нужно будет выполнить позже,
                    # когда пользователь подтвердит начало установки, до этого никаких изменений на диск мы не вносим
                    #используем функцию для создания и открытия крипто-контейнера
                    #create_and_open_crypt_container_by_file "$ext4_partition" "$keyfile"
                    #записываем в качестве девайса для операций, то что ранее было записано функцией save_crypt_container_info
                    #которая была вызвана внутри create_and_open_crypt_container_by_file
                    #current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    current_row["device_for_operations"]="i'm not ready yet" 
                    # в дальнейшем будет обязательная проверка на такое значение и в случае совпадения,
                    # буду выполнены все необходимые операции включая присвоение в это поле девайса для операций
                    # ввиде свежесозданого и открытого luks'а
                    pending_commands_description["$basename_of_ext4_partition"]="Будет отформатировано в LUKS, с ext4 внутри для точек монтирования $mount_point"
                    current_row["pending_commands"]=$(
                    cat <<'EOF'
                    ext4_partition=${current_row["name"]};
                    keyfile=${current_row["keyfile"]};
                    create_and_open_crypt_container_by_file "$ext4_partition" "$keyfile";
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    cureent_row["pending_commands"]=""
EOF
)
                    ;;
                "pwd")
                    #используем функцию для создания и открытия крипто-контейнера
                    #create_and_open_crypt_container_with_new_pwd "$ext4_partition"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    #current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    current_row["device_for_operations"]="i'm not ready yet"
                    pending_commands_description["$basename_of_ext4_partition"]="Будет отформатировано в LUKS, с ext4 внутри для точек монтирования $mount_point"
                    current_row["pending_commands"]=$(
                    cat <<'EOF'
                    ext4_partition=${current_row["name"]};
                    create_and_open_crypt_container_with_new_pwd "$ext4_partition";
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    cureent_row["pending_commands"]=""
EOF
)
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
            current_row["subvolume"]=$subvol_name
            case "$crypt_mode" in
                "none")
                    current_row["device_for_operations"]=$btrfs_device
                    ;;
                "file")
                    #получаем путь к файлу-ключу
                    keyfile=${current_row["keyfile"]}
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_file "$btrfs_device" "$keyfile"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "pwd")
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$btrfs_device"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
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
            current_row["subvolume"]=$subvol_name
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже          
            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[2]}"
                    #т.к. названия группы томов и логического тома ожидается получить от пользователя, то в данном случае
                    #в качестве девайса для операций будет использоваться то, что указал пользователь, а не открытый крипто-контейнер
                    #lvm в данном случае сам всё найдёт по имени группы томов, которой принадлежит в физический том из крипто-контейнера
                    #при этом пользователя надо предупредить о возможной дыре в безопасности, 
                    #если в этой группе томов присутствует хотя бы один физический том, который не зашифрован
                    current_row["device_for_operations"]=$lv_name
                    #используем функцию для открытия крипто-контейнера
                    keyfile=${current_row["keyfile"]}
                    open_crypt_container_by_file "$pv_device" "$keyfile"
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[2]}"
                    current_row["device_for_operations"]=$lv_name
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$pv_device"
                    ;;
                "file_in_none")
                    #получаем путь к файлу-ключу
                    keyfile=${current_row["keyfile"]}
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_file "$btrfs_device" "$keyfile"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "pwd_in_none")
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$btrfs_device"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
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

            #пока что пишем тут команды как будто бы всё было бы сделано сразу, потом закоментируем для откладывания на потом

            size_of_lv=${current_row["size"]}
            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[1]}"
                    #используем функцию для открытия крипто-контейнера
                    keyfile=${current_row["keyfile"]}
                    open_crypt_container_by_file "$pv_device" "$keyfile"
                    opened_lvm_device=${current_row["opened_crypt_container_fullname"]}
                    #
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device="${names[1]}"
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$pv_device"
                    ;;
                "file_in_none")
                    #в этих двух случаях нужно будет создать новые крипто-контейнеры заданного размера
                    # TODO: реализовать функционал по откладыванию на потом создания крипто-контейнеров, 
                    #       но при этом отобразить для пользователя все запланированные изменения
                    #получаем полное имя логического тома
                    lv_name="${names[0]}"
                    #получаем путь к файлу-ключу
                    keyfile=${current_row["keyfile"]}
                    #получаем размер тома
                    size_of_lv=${current_row["size"]}
                    #получаем имя тома и группы томов через функции
                    lv_basename=$(get_lv_name_from_fulldevname "$lv_name")
                    vg_name=$(get_vg_name_from_fulldevname "$lv_name")
                    #создаём логический том заданного размера size_of_lv
                    lvcreate -l "$size_of_lv" -n "$lv_basename" "$vg_name"
                    #создаём крипто-контейнер и открываем его
                    #используем функцию для создания и открытия крипто-контейнера
                    create_and_open_crypt_container_by_file "$lv_name" "$keyfile"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    
                    ;;
                "pwd_in_none")
                    #используем функцию для открытия крипто-контейнера
                    #open_crypt_container_by_pwd "$lv_name"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    #current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
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
    
done
