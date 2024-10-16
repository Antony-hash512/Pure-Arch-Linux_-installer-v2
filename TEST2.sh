#!/bin/bash

echo "Версия bash: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
echo ""
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    :
else
    echo "Требуется Bash версии 4.3 или выше" >&2
    exit 1
fi

: <<'COMMENT'
Примеры использования:
declare -A new_point0=(
    ["mount_point"]="/" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="pwd_in_none" 
    ["name"]="@arch_system_test42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
)

declare -A new_point1=(
    ["mount_point"]="/home" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="key_in_none" 
    ["name"]="@arch_openhome_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
    ["keyfile"]=/etc/home.key
)

возможные значения type: format_ext4, new_subvol_in_btrfs, new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm
возможные значение crypt_mode: (для format_ext4, new_subvol_in_btrfs): none, file, pwd, (для new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm): none_in_none, none_in_file, none_in_pwd, file_in_none, pwd_in_none: (случаи двойного шифорования не рассматриваем из-за избыточности такого действия), file или pwd - какой метод расшифровки будет использован при загрузке системы файл с ключём или пароль?
keyfile: путь к файлу ключа (где создать или откуда использовать), требуется только при использовании опции с file
name: название(я) тома(oв) и/или раздела (для вложенной структуры нужно использовать разделение "_in_" например: @arch_system42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8)
COMMENT

# Создаём ассоциативные массивы для каждой строки "двумерного" массива
# C именем new_point+число
declare -A new_point0=(
    ["mount_point"]="/" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="none_in_none" 
    ["name"]="@arch_system_test42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
)

declare -A new_point1=(
    ["mount_point"]="/home" 
    ["type"]="new_subvol_in_btrfs_in_lvm" 
    ["crypt_mode"]="none_in_none" 
    ["name"]="@arch_openhome_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
)

# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

# Обходим массивы, используя их имена
i=0;
for row in "${ALL_NEW_POINTS[@]}"; do
    ((i++))
    number=$(echo "$row" | grep -o '[0-9]\+')
    echo "$i. (Номер из после \"new_point\": $number)"
    
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    echo "Точка монтирования: ${current_row["mount_point"]}"
    echo "Тип размещения: ${current_row["type"]}"
    echo "Опция Шифрования: ${current_row["crypt_mode"]}"
    echo "Имя (Имена) раздела/томов: ${current_row["name"]}"
    echo ""
done

i=0;
for row in "${ALL_NEW_POINTS[@]}"; do
    ((i++))
    echo "$i. Проводим операции, связанные с точкой монтирования \"${current_row["mount_point"]}\" "
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #case для различных значения ${current_row["type"]}

    # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    echo "Обработка типа: ${current_row["type"]}"
    case "${current_row["type"]}" in
        "format_ext4")            
            # команды для обработки format_ext4
            ext4_path=${current_row["name"]}
            echo "Путь к разделу с ext4: $ext4_path"
            ;;
        "new_subvol_in_btrfs")
            
            # команды для обработки new_subvol_in_btrfs
            subvol_name="${names[0]}"
            btrfs_path="${names[1]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Путь к разделу Btrfs: $btrfs_path"
            ;;
        "new_subvol_in_btrfs_in_lvm")
            # команды для обработки new_subvol_in_btrfs_in_lvm
            
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Логический том LVM (btrfs): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"

            ;;
        "new_ext4_in_lvm")
            
            # команды для обработки new_ext4_in_lvm
            lv_name="${names[0]}"
            lvm_path="${names[1]}"

            echo "Логический том LVM (ext4): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"
            
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
    echo ""
done

read -p "Нажмите Enter для выхода..."
