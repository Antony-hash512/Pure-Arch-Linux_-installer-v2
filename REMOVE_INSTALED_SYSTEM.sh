#!/bin/bash
#данный скрипт надо приспособить для нескольких lvm-разделов и подтомов btrfs

#Служебный каталог для монтирования томов btrfs, добавляем текущую дату и время для уникальности
MOUNT_POINT="/mnt/btrfs_mount_$(date +%Y%m%d_%H%M%S)"

# Примеры использования
# Определение томов lvm для удаления
#LVM_VOLUMES=(
#    "/dev/mainvg/arch_system"
#    "/dev/mainvg/home_system"
#)
# Определение сабволюмов btrfs для удаления
# Ассоциативный массив, где ключ — это устройство, а значение — массив с именами подтомов
# BTRFS_SUBVOLUMES=(
#     ["/dev/mainvg/gigabox"]=("@arch_system" "@home_system")
#     ["/dev/nvme0n1p9"]=("@arch_system_boot")
# )

# Определение томов lvm для удаления
LVM_VOLUMES=("/dev/mainvg/arch_system" "/dev/mainvg/home_system")

# Определение сабволюмов btrfs для удаления
# Ассоциативный массив, где ключ — это устройство, а значение — массив с именами подтомов
declare -A BTRFS_SUBVOLUMES
BTRFS_SUBVOLUMES=(
    ["/dev/mainvg/gigabox"]=("@arch_system @home_system")
)

EFI_NOTE_TO_DELETE=""

# Создаем каталог для точки монтирования, если он не существует
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Создаем каталог точки монтирования: $MOUNT_POINT"
    sudo mkdir -p "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Ошибка при создании каталога $MOUNT_POINT." >&2
        exit 1
    fi
fi

# Отмонтируем каталог, если он уже смонтирован
if mount | grep "$MOUNT_POINT" &>/dev/null; then
    echo "Отмонтируем $MOUNT_POINT, так как он уже смонтирован."
    sudo umount "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Ошибка при отмонтировании $MOUNT_POINT." >&2
        exit 1
    fi
fi

# Удаляем LVM тома
echo "Удаляем тома LVM..."

for volume in "${LVM_VOLUMES[@]}"; do
    echo "Удаляем том: $volume"
    if lvdisplay $volume &>/dev/null; then
        sudo lvremove -y "$volume"
        if [ $? -eq 0 ]; then
            echo "LVM том $volume успешно удалён."
        else
            echo "Ошибка при удалении LVM тома $volume." >&2
        fi
    else
        echo "LVM том $volume не найден."
    fi
done

# Удаляем подтома Btrfs

echo "Удаляем подтома Btrfs..."
for device in "${!BTRFS_SUBVOLUMES[@]}"; do
    #subvolumes=(${BTRFS_SUBVOLUMES[$device]})
    read -r -a subvolumes <<< "${BTRFS_SUBVOLUMES[$device]}"

    echo "Монтируем $device в $MOUNT_POINT"
    sudo mount "$device" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Ошибка при монтировании устройства $device." >&2
        exit 1
    fi

    for subvol in "${subvolumes[@]}"; do
        # Проверяем существование подтома перед удалением
        if sudo btrfs subvolume show "$MOUNT_POINT/$subvol" &>/dev/null; then
            # Удаляем подтом
            echo "Удаляем подтом: $subvol"
            sudo btrfs subvolume delete "$MOUNT_POINT/$subvol"
            if [ $? -ne 0 ]; then
                echo "Ошибка при удалении подтома: $subvol" >&2
            fi
        else
            echo "Подтом $subvol не найден. Пропуск."
        fi
    done

    # Отмонтируем $MOUNT_POINT после удаления
    if mount | grep "$MOUNT_POINT" &>/dev/null; then
        echo "Отмонтируем $MOUNT_POINT"
        sudo umount "$MOUNT_POINT"
        if [ $? -ne 0 ]; then
            echo "Ошибка при отмонтировании $MOUNT_POINT." >&2
            exit 1
        fi
    fi

done

# Завершение работы
# Удаляем служебный каталог для монтирования
if [ -d "$MOUNT_POINT" ]; then
    echo "Удаляем служебный каталог: $MOUNT_POINT"
    sudo rmdir "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Ошибка при удалении каталога $MOUNT_POINT." >&2
    fi
fi

# Удаляем запись EFI, если указано
if [ -n "$EFI_NOTE_TO_DELETE" ]; then
    echo "Удаляем запись EFI: $EFI_NOTE_TO_DELETE"
    sudo efibootmgr -b "$EFI_NOTE_TO_DELETE" -B
    if [ $? -ne 0 ]; then
        echo "Ошибка при удалении записи EFI: $EFI_NOTE_TO_DELETE." >&2
    fi
fi


echo "Удаление системы завершено."
read -p "Нажмите Enter для выхода..."

