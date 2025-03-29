#!/bin/bash

for row in "${ALL_NEW_POINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
     # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    mount_point=${current_row["mount_point"]}

    #в каждый кейс прописан подкейс с опциями шифрования
    #заполняем случаи none_in_none и none
    case "${current_row["type"]}" in
        "format_ext4")            
            ext4_path=${current_row["name"]}
            case "${current_row["crypt_mode"]}" in
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
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs")
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            case "${current_row["crypt_mode"]}" in
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
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs_in_lvm")
            #этот случай польностью протестирован (в режиме none_in_none)
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже


            mkdir -p $INST_DIR$mount_point
            
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                    ;;
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            
            ;;
        "new_ext4_in_lvm")
            lv_name="${names[0]}"
            lv_basename=$(basename "$lv_name")  # Получаем только имя тома
            vg_name=$(echo "$lv_name" | awk -F/ '{print $3}')  # Получаем имя группы томов
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    :
                    ;;
                "none_in_file")
                    :
                    ;;
                "none_in_pwd")
                    :
                    ;;
                "file_in_none")
                    :
                    ;;
                "pwd_in_none")
                    :
                *)
                    echo "Неизвестный тип: ${current_row["crypt_mode"]}" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
    

done