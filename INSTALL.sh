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
SOFT_PACK2="networkmanager btrfs-progs nano mc man-db less links wget git htop p7zip unrar lvm2 cryptsetup cfdisk timeshift"

#дополнительные списки пакетов, которые можно включать и выключать ниже
SOFT_PACK2E="curl ntfs-3g enca dosfstools openvpn os-prober docker tmux diff ncdu ffmpeg mediainfo"
SOFT_PACK2F="neofetch cowsay"
SOFT_PACK2A="alsa-utils pipewire pipewire-pulseaudio sof-firmware mplayer"
SOFT_PACK2B="bluez bluez-utils blueman"
SOFT_PACK2G="openbox gparted xorg-xinit tint2 volumeicon pnmixer volwheel nm-connection-editor network-manager-applet \
obconf alacritty terminator thunar udisks2 gvfs xed gmrun pavucontrol brightnessctl i3lock gsimplecal"
# TODO: проверить нужны ли мне: wmctrl xdotool(авто-действия); gsimplecal - мини-календарь
SOFT_PACK2D="meld geany gtksourceview5"
SOFT_PACK2C="vimdiff, vim, emacs, diff3"
SOFT_PACK2H="firefox chromium vlc viewnior xfce4-screenshooter engrampa"
SOFT_PACK2L="midori feh scrot xarchiver xterm"
SOFT_PACK20="tumbler menumaker conky pinta"
SOFT_PACK21="maim menyoki"
SOFT_PACK22="deluge deluge-gtk gimp inkscape krita timeshift-gtk obsidian"
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



TODO


#uncooment to install more soft:
###########impotant#################
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2E"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2F"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2A"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2B"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2G"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2D"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2C"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2H"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK2L"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK20"
###########extra##################
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK21"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK22"
SOFT_PACK2="$SOFT_PACK2 SOFT_PACK23"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK24"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK25"
#SOFT_PACK2="$SOFT_PACK2 SOFT_PACK26"


#===============конец настроек=============================================================

#Обновление времени
timedatectl set-ntp true

if [[ $INSTALL_FROM =="iso" ]]
    echo "test тест"
    setfont cyr-sun16
    echo "test тест"
fi

#этот шаг нужен, если установка идёт с уже установленной системы
if [[ $INSTALL_FROM =="other_arch_system" ]]
    umount $EFI_LOCATION_4INSTALL_FROM
fi

# Скачивание нужных для установки пакетов
pacman -Suy
packages=("arch-install-scripts" "base" "lvm2" "cryptsetup" "btrfs-progs")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)


# Получаем путь к каталогу, где находится скрипт
script_dir=$(dirname "${BASH_SOURCE[0]}")

# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

ALL_EXTRA_POINTS=()
for var in $(compgen -A variable | grep -E '^extra_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
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
done < "$script_dir/REMOVE_INSTALED_SYSTEM.sh"

if [[ -z "$lvm_single_line" || -z "$btrfs_single_line" ]]; then
    echo "Ошибка: не найдены LVM_VOLUMES или BTRFS_SUBVOLUMES в скрипте REMOVE_INSTALED_SYSTEM.sh" >&2
    exit 1
fi


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
            
            if [[ -v BTRFS_SUBVOLUMES["$btrfs_path"] ]]; then
                BTRFS_SUBVOLUMES["$btrfs_path"]+=" $subvol_name"
            else
                BTRFS_SUBVOLUMES["$btrfs_path"]="$subvol_name"
            fi
            ;;
        "new_subvol_in_btrfs_in_lvm")
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
NEW_SCRIPT_4REMOVE="$script_dir/autocreated_scripts/REMOVE_INSTALED_SYSTEM_${INSTALLATION_NAME}_$(date +%Y-%m-%d_%H-%M).sh"
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
: <<'TODO'
* добавить монтирование уже существующих разделов (в процессе)
* в отдельных кейсах добавить действия по установке

TODO

#начанаем выполять действия по установке

INST_DIR="/mnt/system_installing"

mkdir -p $INST_DIR 
#можно также добавить проверку, что этот каталог не смонтирован



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

mkdir -p $INST_DIR$EFI_NEW_LOCATION
mount $EFI_DEV $INST_DIR$EFI_NEW_LOCATION

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1

# Генерация fstab
genfstab -U $INST_DIR >> $INST_DIR/etc/fstab

#получение имени каталога
#SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

#копирование дополнительного скрипта, для выполнения внутри системы (должен быть в одном каталоге с этим)
cp $script_dir/run_inside_chroot.sh $INST_DIR

#TODO: копирование и распоковка спец-архивов

arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SOFT_PACK2\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/run_inside_chroot.sh 

# Размонтирование всех разделов
umount -R $INST_DIR


echo "ALL DONE"
if [[ $INSTALL_FROM =="other_arch_system" ]]
    mount $EFI_DEV $EFI_LOCATION_4INSTALL_FROM
    echo "не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)"
    read -p "Нажмите Enter для выхода..."
fi
