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

# случаи для legacy будут добавлены потом
EFI_DEV="/dev/nvme0n1p1"
EFI_LOCATION_4INSTALL_FROM="/boot/efi" #только для случая other_arch_system
EFI_NEW_LOCATION="/boot/efi" # точка монтирования для efi в новой системе


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
# далее задаём точки монтирования уже существующих разделов
# будет реализовано позже
declare -A extra_point1=(
    ["mount_point"]="/ntfs/c" 
    ["type"]="in_main_gpt" 
    ["crypt_mode"]="none" 
    ["name"]="/dev/nvme0n1p2"
)
#здесь можно настроить какие пакеты нужно установить вместе с системой
#софт для установки сразу (настоятельно рекомендуется оставить самый необходимый минимум т.к. наличие пакетов здесь не проверяется по отдельности как SOFT_PACK2)
SOFT_PACK1="base base-devel linux linux-firmware"
#софт, который будет установлен на новую систему (тоже сразу, но уже pacman'ом)
SOFT_PACK2="networkmanager btrfs-progs nano vim mc man-db less links wget git htop p7zip unrar lvm2 cryptsetup cfdisk timeshift"

#дополнительные списки пакетов, которые можно включать и выключать ниже
SOFT_PACK2E="curl ntfs-3g enca dosfstools openvpn os-prober docker tmux diff ncdu ffmpeg mediainfo"
SOFT_PACK2F="neofetch cowsay"
SOFT_PACK2A="alsa-utils pipewire pipewire-pulseaudio sof-firmware mplayer"
SOFT_PACK2B="bluez bluez-utils blueman"
SOFT_PACK2G="openbox gparted xorg-xinit tint2 volumeicon pnmixer volwheel nm-connection-editor network-manager-applet \
obconf alacritty terminator thunar udisks2 gvfs xed gmrun pavucontrol brightnessctl i3lock gsimplecal"
# TODO: проверить нужны ли мне: wmctrl xdotool(авто-действия); gsimplecal - мини-календарь
SOFT_PACK2D="meld geany gtksourceview5"
SOFT_PACK2C="vimdiff, emacs, diff3"
SOFT_PACK2H="firefox chromium vlc viewnior xfce4-screenshooter engrampa"
SOFT_PACK2L="midori feh scrot xarchiver xterm"
SOFT_PACK20="tumbler menumaker conky pinta"
SOFT_PACK21="maim menyoki"
SOFT_PACK22="deluge deluge-gtk gimp inkscape krita obsidian"
SOFT_PACK23="qemu-system-x86 virtmanager"
SOFT_PACK24="i2pd tor electrum bitcoin-daemon bitcoin-qt monero p2pool xmrig"
SOFT_PACK25="libreoffice blender doublecmd godot shotcut openshot pitivi obs audacity"
SOFT_PACK26="stacer ananicy"

: <<'TODO'
Добавить свободные шрифты для:
    Оформления часов на панеле
    Отображения символов всех языков

    проверить работоспособность menyoki (для записи видео, создания гифок) или maim(альтернатива scrot)
    узнать подробнее про пакеты
    viewnior — простой просмотрщик изображений.
virtmanager — управление виртуальными машинами.
stacer — мониторинг и оптимизация системы.
ananicy — оптимизация приоритетов процессов.
ffmpegthumbs — генерация миниатюр для видеофайлов.
pureref (нету) — организация изображений для референсов.
obs — запись экрана и стриминг.
shotcut — видеоредактор с открытым исходным кодом.
handbrake — конвертация видео.
oceanaudio-bin — аудиоредактор.
audacious — аудиоплеер.
mediainfo-gui — анализ мультимедийных файлов.
#https://www.youtube.com/watch?v=GPxzcaGErcM


   - Убедитесь, что все пакеты, 
   перечисленные в этих переменных, доступны в репозиториях вашей системы. 
   Вы можете проверить их наличие с помощью команды `pacman -Ss <package_name>`.

TODO


#uncooment to install more soft:
###########impotant#################
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2E"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2F"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2A"
#: <<'NOUSING'
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2B"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2G"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2D"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2C"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2H"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2L"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK20"
###########extra##################
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK21"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK22" #
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK23" #
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK24"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK25"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK26"
#NOUSING

#===============конец настроек=============================================================

#Обновление времени
timedatectl set-ntp true

if [[ $INSTALL_FROM == "iso" ]]; then
    echo "test тест"
    setfont cyr-sun16
    echo "test тест"
fi



# Скачивание нужных для установки пакетов
pacman -Suy
packages=("arch-install-scripts" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)


# Получаем путь к каталогу, где находится скрипт
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

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

#задаём массив для временных точек монтирования
declare -A TEMP_BTRFS_MOUNTPOINTS

# Функция для получения точки монтирования BTRFS устройства
# Аргумент: путь к BTRFS устройству
# Возвращает: путь к точке монтирования
get_btrfs_mountpoint() {
    local btrfs_device="$1"
    local mount_point
    
    # Проверяем, смонтирован ли уже раздел
    if mount_point=$(findmnt -n -o TARGET "$btrfs_device"); then
        echo "$mount_point"
        return 0
    else
        # Создаём временную точку монтирования и монтируем раздел
        #добавляем случайное число и количество секунд по времени unix для уникальности
        local temp_mount="/tmp/temp_btrfs_mount_$(date +%s)_$RANDOM"
        
        mkdir -p "$temp_mount"
        
        if ! mount "$btrfs_device" "$temp_mount"; then
            echo "Ошибка: Не удалось смонтировать $btrfs_device" >&2
            rmdir "$temp_mount"
            return 1
        fi

        #добавляем в массив
        TEMP_BTRFS_MOUNTPOINTS["$btrfs_device"]="$temp_mount"
        
        echo "$temp_mount"
        return 0
    fi
}

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
            btrfs_path="${names[1]}"
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Путь к разделу Btrfs: $btrfs_path"
            # выводим список сабволюмов
            echo "Список существующих подтомов в $btrfs_path:"
            #используем функцию get_btrfs_mountpoint
            if mount_point=$(get_btrfs_mountpoint "$btrfs_path"); then
                btrfs subvolume list "$mount_point"
            else
                echo "Ошибка при монтировании $btrfs_path" >&2
                exit 1
            fi
            #проверяем, что нет уже такого сабтома
            if btrfs subvolume list "$mount_point" | grep -q "$subvol_name"; then
                echo "Ошибка: Подтом с именем $subvol_name уже существует в $btrfs_path" >&2
                exit 1
            else
                echo "имя подтома $subvol_name уникально и будет использовано"
            fi

            
            ;;
        "new_subvol_in_btrfs_in_lvm")
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"
            btrfs_path=$lv_name #аллиас т.к. по смыслу это одно тоже
            echo "Имя субтома Btrfs: $subvol_name"
            echo "Логический том LVM (btrfs): $lv_name"
            echo "Путь к разделу LVM: $lvm_path"
             #используем функцию get_btrfs_mountpoint
            if mount_point=$(get_btrfs_mountpoint "$btrfs_path"); then
                btrfs subvolume list "$mount_point"
            else
                echo "Ошибка при монтировании $btrfs_path" >&2
                exit 1
            fi
            #проверяем, что нет уже такого сабтома
            if btrfs subvolume list "$mount_point" | grep -q "$subvol_name"; then
                echo "Ошибка: Подтом с именем $subvol_name уже существует в $btrfs_path" >&2
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

#размонтирование содержимого массива TEMP_BTRFS_MOUNTPOINTS
for mount_point in "${TEMP_BTRFS_MOUNTPOINTS[@]}"; do
    umount "$mount_point"
    rmdir "$mount_point"
done

echo "Точки монтирования и опции шифрования должны быть настроены путём редактирования данного скрипта"
echo "Корневой каталог должен быть первым, а вложенные быть после родительских"
read -p "Enter - продолжить; ctrl+C - прервать"
echo "Будет создана дополнительна копия скрипта удаления системы, настроенная на удаление данной установки"
read -p "Введите имя установки (будет использовано в имени скрипта для удаления): " INSTALLATION_NAME
NEW_SCRIPT_4REMOVE="$SCRIPT_DIR/autocreated_scripts/REMOVE_INSTALED_SYSTEM_${INSTALLATION_NAME}_$(date +%Y-%m-%d_%H-%M).sh"
cp "$SCRIPT_DIR/REMOVE_INSTALED_SYSTEM.sh" "$NEW_SCRIPT_4REMOVE"

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

# Показываем пользователю список записей EFI
efibootmgr

# Запрашиваем имя нового загрузчика
read -p "Введите имя нового загрузчика в EFI-разделе: " EFI_SYS_NAME

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

# выполняем замену в копии файла REMOVE_INSTALED_SYSTEM.sh
sed -i "s/EFI_NOTE_TO_DELETE=\"\"/EFI_NOTE_TO_DELETE=\"$EFI_SYS_NAME\"/" "$NEW_SCRIPT_4REMOVE"

#продолжаем дописывать скрипт
: <<'TODO'
* добавить монтирование уже существующих разделов (в процессе)
* в отдельных кейсах добавить действия по установке
* дообавить все нужные файлы в архив homefiles.tar.gz

TODO
#=======================================================================================

#ВНИМАНИЕ! тут начинается непосредственно установка

#этот шаг нужен, если установка идёт с уже установленной системы
if [[ $INSTALL_FROM == "other_arch_system" ]]; then
    umount $EFI_LOCATION_4INSTALL_FROM
fi

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

    mount_point = ${current_row["mount_point"]}

    case "${current_row["type"]}" in
        "format_ext4")            
            ext4_path=${current_row["name"]}

        "new_subvol_in_btrfs")
            subvol_name="${names[0]}"
            btrfs_path="${names[1]}"
            ;;
        "new_subvol_in_btrfs_in_lvm")
            subvol_name="${names[0]}"
            lv_name="${names[1]}"
            lvm_path="${names[2]}"

            if ! pacman -Qi "$pkg" &>/dev/null; then
                pacman -S "$pkg" --noconfirm
            fi

            mkdir -p $INST_DIR$mount_point
            
            case "${current_row["crypt_mode"]}" in
                "none_in_none")
                    :
                    mount -o subvol=$subvol_name $lv_name $INST_DIR$mount_point
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
mkdir -p $INST_DIR$EFI_NEW_LOCATION
mount $EFI_DEV $INST_DIR$EFI_NEW_LOCATION

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1

# Генерация fstab
genfstab -U $INST_DIR >> $INST_DIR/etc/fstab


#копирование дополнительного скрипта, для выполнения внутри системы (должен быть в одном каталоге с этим)
cp $SCRIPT_DIR/run_inside_chroot.sh $INST_DIR

#копирование и распоковка архива с файлами для домашнего каталога (будут распаковываны в chroot'е)
cp $SCRIPT_DIR/homefiles.tar.gz $INST_DIR

#-------------------------------
# Chroot в новую систему
# передаём в скрипт список пакетов и имя загрузчика в EFI-разделе
arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SOFT_PACK2\" \"$EFI_SYS_NAME\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/run_inside_chroot.sh 

# Размонтирование всех разделов
umount -R $INST_DIR
rm -rf $INST_DIR


echo "ALL DONE"
if [[ $INSTALL_FROM == "other_arch_system" ]]; then
    mount $EFI_DEV $EFI_LOCATION_4INSTALL_FROM
    echo "не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)"
    read -p "Нажмите Enter для выхода..."
else
    echo "Установка завершена. Перезагрузите компьютер."
fi




