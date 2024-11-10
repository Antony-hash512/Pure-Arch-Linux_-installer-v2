#!/bin/bash

echo "Версия bash: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
echo ""
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    :
else
    echo "Требуется Bash версии 4.3 или выше" >&2
    exit 1
fi

# Скачивание нужных для установки пакетов
echo "Вы хотите обновить всю вашу систему перед установкой или установить только необходимые пакеты?"
echo "Введите \"skip\", чтобы установить только необходимые пакеты не обновляя систему или Enter - обновить систему"
read UPDATE_SYSTEM
if [[ $UPDATE_SYSTEM == "skip" ]]; then
    echo "Полное обновление системы пропущено"
    echo "Будет выполнено только обновление базы пакетов перед установкой нужных"
    pacman -Sy
else
    echo "Обновление системы"
    pacman -Syu
fi
packages=("arch-install-scripts" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr" "python")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)

#получаем список всех систем настроенных в systems.xml
ALL_SYSTEM_IDS="$(python3 get_data_from_xml.py list_system_ids)"
echo "В файле systems.xml найдены настройки следующих систем: $ALL_SYSTEM_IDS"

read -p "Введите id системы для установки:" SYSTEM_ID
# Проверяем уникальность имени и предлагаем варианты
while true; do 
    if echo "$ALL_SYSTEM_IDS" | grep -qw "$SYSTEM_ID"; then
        echo "Используем настройки системы с id $SYSTEM_ID"
        break
    else
        echo "Система с id $SYSTEM_ID не найдена в файле systems.xml"
        echo "Введите другой id системы для установки или совершите выход при помощи ctrl+C"
        echo "В файле systems.xml найдены настройки следующих систем: $ALL_SYSTEM_IDS"
        read -p "Введите существующий в файле systems.xml id системы для установки:" SYSTEM_ID
    fi
done


# откуда устанавливается система
if [[ $(python3 get_data_from_xml.py $SYSTEM_ID get_tweak_iso) == "true" ]]; then
    INSTALL_FROM="iso"
else
    INSTALL_FROM="other_arch_system"
fi

# случаи для legacy будут добавлены потом

EFI_DEV="$(python3 get_data_from_xml.py $SYSTEM_ID get_efi_dev)"
EFI_NEW_LOCATION="$(python3 get_data_from_xml.py $SYSTEM_ID get_efi_new_location)"


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

для уже существующих разделов значения type немного отличаются:
in_main_gpt, subvol_in_btrfs, subvol_in_btrfs_in_lvm, volume_in_lvm

пример:
declare -A extra_point1=(
    ["mount_point"]="/ntfs/c" 
    ["type"]="in_main_gpt" 
    ["crypt_mode"]="none" 
    ["name"]="/dev/nvme0n1p2"
)

COMMENT

# Создаём ассоциативные массивы для каждой строки "двумерного" массива
# C именем new_point+число
# корневой каталог должен быть первым, а вложенные быть после родительских
# получаем количество точек монтирования
ALL_NEW_POINTS_COUNT="$(python3 get_data_from_xml.py $SYSTEM_ID get_amount_of_new_mountpoints)"
ALL_EXTRA_POINTS_COUNT="$(python3 get_data_from_xml.py $SYSTEM_ID get_amount_of_extra_mountpoints)"
# создаём массивы для новых точек монтирования
for ((i=0; i<ALL_NEW_POINTS_COUNT; i++)); do
    declare -A new_point$i="$(python3 get_data_from_xml.py $SYSTEM_ID get_new_mountpoint $i)"
done
# создаём массивы для дополнительных точек монтирования
for ((i=0; i<ALL_EXTRA_POINTS_COUNT; i++)); do
    declare -A extra_point$i="$(python3 get_data_from_xml.py $SYSTEM_ID get_extra_mountpoint $i)"
done



## будет реализовано позже
#declare -A extra_point1=(
#    ["mount_point"]="/ntfs/c" 
#    ["type"]="in_main_gpt" 
#    ["crypt_mode"]="none" 
#    ["name"]="/dev/nvme0n1p2"
#)


#получаем список пакетов для pacstrap
SOFT_PACK1="$(python3 get_data_from_xml.py $SYSTEM_ID get_pkgs_pacstrap)"

#===============конец настроек=============================================================

#Обновление времени
timedatectl set-ntp true



if [[ $INSTALL_FROM == "iso" ]]; then
    echo "test тест"
    setfont cyr-sun16
    echo "test тест"
fi

# Получаем путь к каталогу, где находится скрипт
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

# Показываем пользователю список записей EFI
efibootmgr

EFI_SYS_NAME="$(python3 get_data_from_xml.py $SYSTEM_ID get_efi_bootlabel)"

# Проверяем уникальность имени и предлагаем варианты
while true; do
    if efibootmgr | grep -q "$EFI_SYS_NAME"; then
        echo "Загрузчик с именем $EFI_SYS_NAME уже существует."
        read -p "Хотите перезаписать существующий загрузчик? (type YES using Capital letters): " overwrite
        if [[ $overwrite =~ ^YES$ ]]; then
            echo "Будет выполнена перезапись существующего загрузчика."
            break
        else
            read -p "Введите другое имя загрузчика в EFI-разделе: " EFI_SYS_NAME
        fi
    else
        echo "Имя загрузчика $EFI_SYS_NAME уникально и будет использовано."
        break
    fi
done

# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

ALL_EXTRA_POINTS=()
for var in $(compgen -A variable | grep -E '^extra_point[0-9]+$'); do
    ALL_EXTRA_POINTS+=("$var")
done

lsblk
echo "разделы должны быть созданы заранее вручную, автоматически создаются только тома на них"
read -p "Enter - продолжить; ctrl+C - прервать"


# Задаём массивы для последующей записи в дополнительно созданый скрипт для удаления системы
LVM_VOLUMES=()
declare -A BTRFS_SUBVOLUMES

#определяем как там заданы массивы в одну строчку или нет
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
done < "$SCRIPT_DIR/REMOVE_INSTALED_SYSTEM.sh"

if [[ -z "$lvm_single_line" || -z "$btrfs_single_line" ]]; then
    echo "Ошибка: не найдены LVM_VOLUMES или BTRFS_SUBVOLUMES в скрипте REMOVE_INSTALED_SYSTEM.sh" >&2
    exit 1
fi


#ассоциативный массив для хранения точек монтирования корневых разделов всех btrfs
declare -A ALL_ROOT_BTRFS_MOUNTPOINTS

#####начало отладки
echo "ALL_NEW_POINTS: ${ALL_NEW_POINTS[@]}"
#вывод всех элементов массива
for item in "${ALL_NEW_POINTS[@]}"; do
    echo "$item"
    declare -n current_array="$item"
    for key in "${!current_array[@]}"; do
        echo "[$key]=${current_array[$key]}"
    done
done    

echo "ALL_EXTRA_POINTS: ${ALL_EXTRA_POINTS[@]}" 
#вывод всех элементов массива   
for item in "${ALL_EXTRA_POINTS[@]}"; do
    echo "$item"
done    




#####конец отладки



# Обходим массивы, используя их имена
i=0;
for row in "${ALL_NEW_POINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    if [[ "$i" -eq 0 && "${current_row["mount_point"]}" != "/" ]]; then
        echo "Ошибка: первой должна быть /" >&2
        exit 1
    fi
    ((i++))
    number=$(echo "$row" | grep -o '[0-9]\+')
    echo "$i. (Номер из после \"new_point\": $number)"
    
    
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
            ext4_path=${current_row["name"]}
            echo "Путь к разделу с ext4: $ext4_path"
            ;;
        "new_subvol_in_btrfs")
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Путь к разделу Btrfs: $btrfs_device"
            #проверяем что этого раздела нет в массиве
            if [[ ! -v ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"] ]]; then
                #получаем имя точки монтирования используя время unix и случайное число
                CURRENT_BTRFS_MOUNTPOINT="/mnt/btrfs_root_$(date +%s)_$RANDOM"
                ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]="$CURRENT_BTRFS_MOUNTPOINT"
                #создаём каталог для точки монтирования
                mkdir -p "$CURRENT_BTRFS_MOUNTPOINT"
                #монтируем раздел
                mount "$btrfs_device" "$CURRENT_BTRFS_MOUNTPOINT"
            fi



            # выводим список сабволюмов
            btrfs_subvolumes_str=$(echo "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}"| xargs -I {} sudo btrfs subvolume list {})           
            echo "Список существующих подтомов в $btrfs_device:"
            echo "$btrfs_subvolumes_str"
            #проверяем, что нет уже такого сабтома
            if echo "$btrfs_subvolumes_str" | grep -q "$subvol_name"; then
                echo "Ошибка: Подтом с именем $subvol_name уже существует в $btrfs_device" >&2
                exit 1
            else
                echo "имя подтома $subvol_name уникально и будет использовано"
            fi
           

            
            ;;
        "new_subvol_in_btrfs_in_lvm")
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Логический том LVM (btrfs): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"

            #проверяем что этого раздела нет в массиве
            if [[ ! -v ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"] ]]; then
                #получаем имя точки монтирования используя время unix и случайное число
                CURRENT_BTRFS_MOUNTPOINT="/mnt/btrfs_root_$(date +%s)_$RANDOM"
                ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]="$CURRENT_BTRFS_MOUNTPOINT"
                #создаём каталог для точки монтирования
                mkdir -p "$CURRENT_BTRFS_MOUNTPOINT"    
                #монтируем раздел
                mount "$btrfs_device" "$CURRENT_BTRFS_MOUNTPOINT"
            fi

            btrfs_subvolumes_str=$(echo "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}"| xargs -I {} sudo btrfs subvolume list {})           
            echo "Список существующих подтомов в $btrfs_device:"
            echo "$btrfs_subvolumes_str"

            #проверяем, что нет уже такого сабтома
            if echo "$btrfs_subvolumes_str" | grep -q "$subvol_name"; then
                echo "Ошибка: Подтом с именем $subvol_name уже существует в $btrfs_device" >&2
                exit 1
            else
                echo "имя подтома $subvol_name уникально и будет использовано"
            fi
           

            if [[ -v BTRFS_SUBVOLUMES["$lv_name"] ]]; then
                BTRFS_SUBVOLUMES["$lv_name"]+=" $subvol_name"
            else
                BTRFS_SUBVOLUMES["$lv_name"]="$subvol_name"
            fi
            ;;
        "new_ext4_in_lvm")
            lv_name="${names[0]}"
            lvm_path="${names[1]}"
            echo "Логический том LVM (ext4): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"
            # Проверяем, существует ли уже логический том с именем $lv_name
            if lvdisplay "$lvm_path/$lv_name" &> /dev/null; then
                echo "Ошибка: Логический том с именем $lv_name уже существует в $lvm_path" >&2
                exit 1
            fi
            
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


echo "Точки монтирования и опции шифрования должны быть настроены путём редактирования файла systems.xml"
echo "Корневой каталог должен быть первым, а вложенные быть после родительских"
read -p "Enter - продолжить; ctrl+C - прервать"
echo "Будет создана дополнительна копия скрипта удаления системы, настроенная на удаление данной установки"
INSTALLATION_NAME="$SYSTEM_ID"
NEW_SCRIPT_4REMOVE="$SCRIPT_DIR/autocreated_scripts/REMOVE_INSTALED_SYSTEM_${INSTALLATION_NAME}_$(date +%Y-%m-%d_%H-%M).sh"
cp "$SCRIPT_DIR/REMOVE_INSTALED_SYSTEM.sh" "$NEW_SCRIPT_4REMOVE"


#### начало создания скрипта удаления
# Создаём строки для LVM_VOLUMES и BTRFS_SUBVOLUMES
lvm_volumes_str=""
for volume in "${LVM_VOLUMES[@]}"; do
    lvm_volumes_str+="    \"$volume\"\n"
done

# Записываем содержимое BTRFS_SUBVOLUMES в переменную в формате ["ключ"]="значения"
btrfs_subvolumes_str=""
for key in "${!BTRFS_SUBVOLUMES[@]}"; do
    btrfs_subvolumes_str+="    [\"$key\"]=\"${BTRFS_SUBVOLUMES[$key]}\"\n"
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


# выполняем замену в копии файла REMOVE_INSTALED_SYSTEM.sh
sed -i "s/EFI_NOTE_TO_DELETE=\"\"/EFI_NOTE_TO_DELETE=\"$EFI_SYS_NAME\"/" "$NEW_SCRIPT_4REMOVE"

#### конец создания скрипта удаления 

#продолжаем дописывать скрипт
: <<'TODO'
* написать код для всех случаев с lvm, btrfs и опций шифрования
* добавить монтирование уже существующих разделов (в процессе)
* релизовать и протестировать поддержку других систем инициализации на случай установки Artix
* упорядочить код, так чтобы все что отвечает за создание копии скрипта удаления было в одном блоке
* разобраться что не так с удалением сабволюмов через автоматический скрипт
TODO
#=======================================================================================

#ВНИМАНИЕ! тут начинается непосредственно установка


#добавляем к имени каталога текущую дату и время для уникальности
INST_DIR="/mnt/system_installing_$(date +%Y-%m-%d_%H-%M)"

mkdir -p $INST_DIR 
#проверка, что этот каталог не смонтирован
if mount | grep -q $INST_DIR; then
    echo "Ошибка: каталог $INST_DIR уже смонтирован" >&2
    exit 1
fi



for row in "${ALL_NEW_POINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
     # Разбивка строки с разделителем "_in_" и запись значений в переменные
    spaced_names="${current_row["name"]//_in_/ }"
    # Преобразуем строку в массив по пробелам
    read -r -a names <<< "$spaced_names"

    mount_point=${current_row["mount_point"]}

    case "${current_row["type"]}" in
        "format_ext4")            
            ext4_path=${current_row["name"]}
            ;;
        "new_subvol_in_btrfs")
            subvol_name="${names[0]}"
            btrfs_device="${names[1]}"
            ;;
        "new_subvol_in_btrfs_in_lvm")
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже

            if ! pacman -Qi "$pkg" &>/dev/null; then
                pacman -S "$pkg" --noconfirm
            fi

            mkdir -p $INST_DIR$mount_point
            
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    #создаём подтом
                    btrfs subvolume create "${ALL_ROOT_BTRFS_MOUNTPOINTS["$btrfs_device"]}/$subvol_name"
                    #монтируем подтом в каталог установки (внутри chroot'а)
                    mount -o subvol=$subvol_name $btrfs_device $INST_DIR$mount_point
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
            lvm_path="${names[1]}"
            ;;
        *)
            echo "Неизвестный тип: ${current_row["type"]}" >&2
            exit 1
            ;;
    esac
    

done

#монтируем раздел EFI
mkdir -p $INST_DIR/$EFI_NEW_LOCATION
mount $EFI_DEV $INST_DIR/$EFI_NEW_LOCATION

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1

# Генерация fstab
genfstab -U $INST_DIR >> $INST_DIR/etc/fstab


#копирование дополнительного скрипта, для выполнения внутри системы (должен быть в одном каталоге с этим)
cp $SCRIPT_DIR/run_inside_chroot.sh $INST_DIR
cp $SCRIPT_DIR/get_data_from_xml.py $INST_DIR
cp $SCRIPT_DIR/systems.xml $INST_DIR


#получаем список архивов для распаковки в домашнюю папку пользователя
ARCHIVES_4HOME="$(python3 get_data_from_xml.py $SYSTEM_ID get_archs4home)"

#копирование и распоковка архивов с файлами для домашнего каталога (будут распаковываны в chroot'е)
for archive in $ARCHIVES_4HOME; do
    cp $SCRIPT_DIR/$archive $INST_DIR
done

#-------------------------------
# Chroot в новую систему
# передаём в скрипт список пакетов и имя загрузчика в EFI-разделе
arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SYSTEM_ID\" \"$EFI_SYS_NAME\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/run_inside_chroot.sh
rm $INST_DIR/get_data_from_xml.py
rm $INST_DIR/systems.xml

#размонтируем раздел EFI
umount $INST_DIR/$EFI_NEW_LOCATION

# Размонтирование всех разделов
umount -R $INST_DIR
if [ -z "$(ls -A $INST_DIR)" ]; then
    rmdir $INST_DIR
else
    echo "Каталог $INST_DIR не пустой. Удаление не выполнено."
fi

#размонтирование всех разделов btrfs
for btrfs_path in "${ALL_ROOT_BTRFS_MOUNTPOINTS[@]}"; do
    umount "$btrfs_path"
done
#удаление пустых каталогов точек монтирования
for btrfs_path in "${ALL_ROOT_BTRFS_MOUNTPOINTS[@]}"; do
    rmdir "$btrfs_path"
done


echo "ALL DONE"
if [[ $INSTALL_FROM == "other_arch_system" ]]; then
    echo "не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)"
    read -p "Нажмите Enter для выхода..."
else
    echo "Установка завершена. Перезагрузите компьютер."
fi

