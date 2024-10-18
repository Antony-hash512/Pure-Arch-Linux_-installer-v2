#!/bin/bash

echo "Версия bash: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
echo ""
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    :
else
    echo "Требуется Bash версии 4.3 или выше" >&2
    exit 1
fi

# откуда устанавливается система
INSTALL_FROM="other_arch_system" # other_arch_system - с уже установленного Арча, iso - с LiveCD/DVD/USB

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

* возможные значения type: format_ext4, new_subvol_in_btrfs, new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm
* возможные значение crypt_mode: (для format_ext4, new_subvol_in_btrfs): none, file, pwd, (для new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm): none_in_none, none_in_file, none_in_pwd, file_in_none, pwd_in_none: (случаи двойного шифорования не рассматриваем из-за избыточности такого действия), file или pwd - какой метод расшифровки будет использован при загрузке системы файл с ключём или пароль?
* keyfile: путь к файлу ключа (где создать или откуда использовать), требуется только при использовании опции с file
* name: название(я) тома(oв) и/или раздела (для вложенной структуры нужно использовать разделение "_in_" например: @arch_system42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8)
COMMENT

# Создаём ассоциативные массивы для каждой строки "двумерного" массива
# C именем new_point+число
# корневой каталог должен быть первым, а вложенные быть после родительских
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
#===============конец настроек=============================================================

# Получаем путь к каталогу, где находится скрипт
script_dir=$(dirname "${BASH_SOURCE[0]}")

# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

lsblk
echo "разделы должны быть созданы заранее вручную, автоматически создаются только тома на них"
read -p "Enter - продолжить; ctrl+C - прервать"


# Задаём массивы для последующей записи в дополнительно созданый скрипт для удаления системы
LVM_VOLUMES=()
declare -A BTRFS_SUBVOLUMES

#определяем как там заданы массивы в одну строчку для нет
lvm_single_line=''
btrfs_single_line=''

while IFS= read -r line; do
    if [[ "$line" =~ ^LVM_VOLUMES=\(.*\)$ ]]; then
        lvm_single_line='true'
    elif [[ "$line" =~ ^LVM_VOLUMES=\([^\)]*$ ]]; then
        lvm_single_line='false'
    elif [[ "$line" =~ ^BTRFS_SUBVOLUMES=\(.*\)$ ]]; then
        btrfs_single_line='true'
    elif [[ "$line" =~ ^BTRFS_SUBVOLUMES=\([^\)]*$ ]]; then
        btrfs_single_line='false'
    fi
done < "$script_dir/REMOVE_INSTALED_SYSTEM.sh"

if [[ -z "$lvm_single_line" || -z "$btrfs_single_line" ]]; then
    echo "Ошибка: не найдены LVM_VOLUMES или BTRFS_SUBVOLUMES в скрипте REMOVE_INSTALED_SYSTEM.sh" >&2
    exit 1
fi


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

    # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

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
            
            if [[ -v BTRFS_SUBVOLUMES["$btrfs_path"] ]]; then
                BTRFS_SUBVOLUMES["$btrfs_path"]+=" $subvol_name"
            else
                BTRFS_SUBVOLUMES["$btrfs_path"]="$subvol_name"
            fi
            ;;
        "new_subvol_in_btrfs_in_lvm")
            # команды для обработки new_subvol_in_btrfs_in_lvm
            
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Логический том LVM (btrfs): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"

            if [[ -v BTRFS_SUBVOLUMES["$lv_name"] ]]; then
                BTRFS_SUBVOLUMES["$lv_name"]+=" $subvol_name"
            else
                BTRFS_SUBVOLUMES["$lv_name"]="$subvol_name"
            fi
            ;;
        "new_ext4_in_lvm")
            
            # команды для обработки new_ext4_in_lvm
            lv_name="${names[0]}"
            lvm_path="${names[1]}"
            echo "Логический том LVM (ext4): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"
            
            # Добавляем lv_name в массив LVM_VOLUMES
            LVM_VOLUMES+=("$lv_name")
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
    printf "\n\n\n"
done

echo "Точки монтирования и опции шифрования должны быть настроены путём редактирования данного скрипта"
echo "Корневой каталог должен быть первым, а вложенные быть после родительских"
read -p "Enter - продолжить; ctrl+C - прервать"
echo "Будет создана дополнительна копия скрипта удаления системы, настроенная на удаление данной установки"
read -p "Введите имя установки (будет использовано в имени скрипта для удаления): " INSTALLATION_NAME
NEW_SCRIPT_4REMOVE="$script_dir/REMOVE_INSTALED_SYSTEM_${INSTALLATION_NAME}_$(date +%Y-%m-%d_%H-%M).sh"
cp "$script_dir/REMOVE_INSTALED_SYSTEM.sh" "$NEW_SCRIPT_4REMOVE"

# Создаём строки для LVM_VOLUMES и BTRFS_SUBVOLUMES
lvm_volumes_str=""
for volume in "${LVM_VOLUMES[@]}"; do
    lvm_volumes_str+="    \"$volume\"\n"
done


# Записываем содержимое BTRFS_SUBVOLUMES в переменную в формате ["ключ"]=("значения")
btrfs_subvolumes_str=""
for key in "${!BTRFS_SUBVOLUMES[@]}"; do
    btrfs_subvolumes_str+="    [\"$key\"]=(\"${BTRFS_SUBVOLUMES[$key]}\")\n"
done

# Переводим символы новой строки (\n) в литеральные символы, чтобы sed корректно обработал
lvm_volumes_str=$(echo -e "$lvm_volumes_str")
btrfs_subvolumes_str=$(echo -e "$btrfs_subvolumes_str")

# Экранируем все слеши в переменных, чтобы корректно работать с sed
lvm_volumes_str=$(echo "$lvm_volumes_str" | sed 's/\//\\\//g')
btrfs_subvolumes_str=$(echo "$btrfs_subvolumes_str" | sed 's/\//\\\//g')

# закоменчиваем старые значения
case "$lvm_single_line" in
    'false')
        sed -i '/^LVM_VOLUMES=(/,/^)/ {/^LVM_VOLUMES=(/!{/^)/!s/^/# /}}' "$NEW_SCRIPT_4REMOVE"
        ;;
    'true')
        sed -i 's/^LVM_VOLUMES=(/LVM_VOLUMES=(#/' "$NEW_SCRIPT_4REMOVE"
        sed -i '/^LVM_VOLUMES=(#/a )' "$NEW_SCRIPT_4REMOVE"
        ;;
    *)
        echo "Ошибка: неизвестное значение для lvm_single_line" >&2
        exit 1
        ;;
esac

case "$btrfs_single_line" in
    'false')
        sed -i '/^BTRFS_SUBVOLUMES=(/,/^)/ {/^BTRFS_SUBVOLUMES=(/!{/^)/!s/^/# /}}' "$NEW_SCRIPT_4REMOVE"
        ;;
    'true')
        sed -i 's/^BTRFS_SUBVOLUMES=(/BTRFS_SUBVOLUMES=(#/' "$NEW_SCRIPT_4REMOVE"
        sed -i '/^BTRFS_SUBVOLUMES=(#/a )' "$NEW_SCRIPT_4REMOVE"
        ;;
    *)
        echo "Ошибка: неизвестное значение для btrfs_single_line" >&2
        exit 1
        ;;
esac

# Вставляем новые значения после строки ^LVM_VOLUMES=( 
while IFS= read -r line; do
    sed -i "/^LVM_VOLUMES=(/a \\
$line" "$NEW_SCRIPT_4REMOVE"
done <<< "$lvm_volumes_str"

# Вставляем новые значения после строки ^BTRFS_SUBVOLUMES=( 
while IFS= read -r line; do
    sed -i "/^BTRFS_SUBVOLUMES=(/a \\
$line" "$NEW_SCRIPT_4REMOVE"
done <<< "$btrfs_subvolumes_str"


#продолжаем дописывать скрипт




read -p "Нажмите Enter для выхода..."

