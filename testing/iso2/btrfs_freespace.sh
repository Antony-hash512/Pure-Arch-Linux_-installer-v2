#!/bin/bash
debag=0

# создаём массив для хранения разделов btrfs
declare -a btrfs_devices

# Получаем список и сразу пропускаем заголовок (опция --noheadings)
lsblk_output=$(lsblk --noheadings -l -o NAME,TYPE,FSTYPE)

# Используем readarray для чтения в массив (избегаем подоболочку)
readarray -t lines <<< "$lsblk_output"

for line in "${lines[@]}"; do
    # Отладочный вывод
    if [ "$debag" == "1" ]; then
        echo "Обрабатываем строку: $line"
    fi
    
    device=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    fstype=$(echo "$line" | awk '{print $3}')
    
    # Отладочный вывод
    if [ "$debag" == "1" ]; then
        echo "  device=$device, type=$type, fstype=$fstype"
    fi
    
    if [ "$fstype" == "btrfs" ]; then
        if [ "$type" == "part" ]; then
            device_name="/dev/$device"
            btrfs_devices+=("$device_name")
        elif [ "$type" == "lvm" ]; then
            device_name="/dev/mapper/$device"
            btrfs_devices+=("$device_name")
        fi
    fi
done

echo "Найденные btrfs устройства:"
for i in "${!btrfs_devices[@]}"; do
    echo "$((i+1)). ${btrfs_devices[$i]}"
done

echo "Введите номер btrfs устройства:"
read -r device_number

while true; do
    if [[ "$device_number" =~ ^[0-9]+$ ]] && [ "$device_number" -ge 1 ] && [ "$device_number" -le "${#btrfs_devices[@]}" ]; then
        selected_device="${btrfs_devices[$((device_number-1))]}"
        echo "Выбрано устройство: $selected_device"
        break
    else
        echo "Ошибка: Неверный номер устройства" >&2
        echo "Введите номер btrfs устройства (от 1 до ${#btrfs_devices[@]}):"
        read -r device_number
    fi
done

SELECTED_DEVICE=$selected_device

OPTIONS=("Просмотреть свободное пространство" "Просмотреть гарантированное свободное пространство" "Полный выхлоп")

echo "Выберите опцию:"
for i in "${!OPTIONS[@]}"; do
    echo "$((i+1)). ${OPTIONS[$i]}"
done

read -r option_number

if [[ "$option_number" =~ ^[0-9]+$ ]] && [ "$option_number" -ge 1 ] && [ "$option_number" -le "${#OPTIONS[@]}" ]; then
    SELECTED_OPTION="${OPTIONS[$((option_number-1))]}"
    echo "Выбрана опция: $SELECTED_OPTION"
else
    echo "Ошибка: Неверный номер опции" >&2
    exit 1
fi

# Монтируем $SELECTED_DEVICE по временный каталог
TEMP_MOUNT_POINT=$(mktemp -d)
sudo mount $SELECTED_DEVICE $TEMP_MOUNT_POINT



case $SELECTED_OPTION in
    "Просмотреть свободное пространство")
        sudo btrfs filesystem usage -h $TEMP_MOUNT_POINT | grep min | awk '{print $3}'
        ;;
    "Просмотреть гарантированное свободное пространство")
        sudo btrfs filesystem usage -h $TEMP_MOUNT_POINT | grep min | awk '{print $5}'
        ;;
    "Полный выхлоп")
        sudo btrfs filesystem usage -h $TEMP_MOUNT_POINT
        ;;
    *)
        echo "Ошибка: Неверный номер опции" >&2
        exit 1
        ;;
esac

sudo umount $TEMP_MOUNT_POINT
rmdir $TEMP_MOUNT_POINT
