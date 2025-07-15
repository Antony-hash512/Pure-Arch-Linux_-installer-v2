#!/bin/bash

source ../include/shared_functions.sh
sync_time
CURRENT_DAY=$(date +%d)
CURRENT_MONTH=$(date +%m)
CURRENT_YEAR=$(date +%Y)
RAM_SIZE=4G
CPU_CORES=4
UPDATE_ISO=false
DEFAULT_DISK='[modified]archlinux_vm_disk.qcow2'
DISK_NAME="$DEFAULT_DISK"

# Обработка пользовательских аргументов
while [[ $# -gt 0 ]]; do
    case "$1" in
        --alt-disk)
            if [[ -z "$2" ]]; then
                echo "Параметр --alt-disk требует указать имя файла."
                exit 1
            fi
            DISK_NAME="$2"
            shift 2
            ;;
        *)
            echo "Неизвестный параметр: $1"
            echo "Доступные параметры: --alt-disk <файл>"
            exit 1
            ;;
    esac
done

if [ ! -f [original]archlinux_vm_disk.qcow2 ] && [ $DISK_NAME == $DEFAULT_DISK ]; then
    echo "Ошибка: не найден оригинальный образ диска [original]archlinux_vm_disk.qcow2"
    echo "Пожалуйста, создайте его с помощью скрипта ./create_parted_qcow2.sh"
    echo "Подробности в файле README.md"
    exit 1
fi

if [ ! -f [modified]OVMF_VARS.4m.fd ]; then
    cp [original]OVMF_VARS.4m.fd [modified]OVMF_VARS.4m.fd
fi

if [ ! -f [modified]archlinux_vm_disk.qcow2 ]; then
    cp [original]archlinux_vm_disk.qcow2 [modified]archlinux_vm_disk.qcow2
fi

#из-за разницы в часовых поясах и риска задержки релиза, в первые 2 дня проверяем за прошлый месяц
#но если образ за текущий месяц есть (например, добавлен вручную), то не отматываем месяц назад
if [ $CURRENT_DAY -le 2 ] && [ ! -f archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso ]; then
    if [ $CURRENT_MONTH -eq 01 ]; then
        CURRENT_MONTH=12
        CURRENT_YEAR=$((CURRENT_YEAR - 1))
    else
        CURRENT_MONTH=$(printf "%02d" $((10#$CURRENT_MONTH - 1)))
    fi
fi

#проверяем отсутствие образа за любой месяц и год
# Если в каталоге отсутствуют *какие-либо* ISO-образы Arch Linux,
# сразу помечаем необходимость скачивания
if ! compgen -G "archlinux-*.iso" > /dev/null; then
    echo "В каталоге не найдено ни одного ISO образа Arch Linux."
    UPDATE_ISO=true
fi

# если пролое условие не выполнилось, то проверяем, нужно ли обновлять образ
if [ ! -f archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso ] && [ $UPDATE_ISO -eq false ]; then
    echo "Хотите обновить образ Arch Linux? (y/N)"
    read -r response
    if [[ "$response" =~ ^[YyДд]$ ]]; then
        UPDATE_ISO=true
    fi
fi

# Скачиваем ISO, если это необходимо
if [ "$UPDATE_ISO" = true ]; then
    if ! pacman -Qi aria2 &>/dev/null; then
        sudo pacman -S aria2 --noconfirm
    fi
    if ! pacman -Qi wget &>/dev/null; then
        sudo pacman -S wget --noconfirm
    fi
    if [ -f arch.torrent ]; then
        rm arch.torrent
    fi
    wget https://archlinux.org/releng/releases/$(date +%Y).$(date +%m).01/torrent/ -O arch.torrent
    aria2c arch.torrent --enable-rpc=false --seed-time=0
    # Проверяем, что файл архива существует
    if [ -f archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso ]; then
        echo "Скачивание завершено успешно!"
        # Удаляем старые образы ISO (кроме текущего)
        for iso_file in archlinux-*.iso; do
            if [ -f "$iso_file" ] && [ "$iso_file" != "archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso" ]; then
                echo "Удаляем старый образ: $iso_file"
                rm "$iso_file"
            fi
        done        
        # Удаляем соответствующие .aria2 файлы
        for aria2_file in archlinux-*.iso.aria2; do
            if [ -f "$aria2_file" ] && [ "$aria2_file" != "archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso.aria2" ]; then
                echo "Удаляем файл aria2: $aria2_file"
                rm "$aria2_file"
            fi
        done
    else
        echo "Произошла ошибка при скачивании."
        exit 1
    fi
fi

if ! pacman -Qi qemu-base &>/dev/null; then
    sudo pacman -S qemu-base --noconfirm
fi

qemu-system-x86_64 \
    -enable-kvm \
    -m ${RAM_SIZE} \
    -cpu host \
    -smp ${CPU_CORES} \
    -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=[modified]OVMF_VARS.4m.fd \
    -drive file=${DISK_NAME},format=qcow2 \
    -virtfs local,path=../,mount_tag=inst_scripts,security_model=none \
    -cdrom archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso \
    -drive file=./mntfld.iso,media=cdrom \
    -boot order=d \
    -netdev user,id=mynet0 \
    -device virtio-net-pci,netdev=mynet0 \
    -display gtk,zoom-to-fit=off \
    -device virtio-vga,edid=on,xres=1280,yres=720 \

    #-audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native \
    #-device intel-hda \
    #-device hda-duplex,audiodev=pa

