#!/bin/bash
#данный скрипт надо приспособить для нескольких lvm-разделов и подтомов btrfs

MOUNT_POINT="/mnt/btrfs_mount"

#Примеры использования
#LVM_VOLUMES=(
#    "/dev/mainvg/arch_system"
#    "/dev/mainvg/home_system"
#)
#BTRFS_SUBVOLUMES=(
#    "@arch_system /dev/mainvg/gigabox"
#    "@home_system /dev/mainvg/gigabox"
#)


# Установка переменных (должно автоматически заполнится после установки
# Определение томов LVM для удаления
LVM_VOLUMES=(
    "/dev/mainvg/arch_system"
    "/dev/mainvg/home_system"
)

# Определение томов LVM для удаления
BTRFS_SUBVOLUMES=(
    "@arch_system /dev/mainvg/gigabox"
    "@home_system /dev/mainvg/gigabox"
)

EFI_NOTE_TO_DELETE=""


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

# Монтирование Btrfs-раздела
echo "Монтирование Btrfs-раздела: $BTRFS_DEVICE"
sudo mkdir -p $MOUNT_POINT
sudo mount $BTRFS_DEVICE $MOUNT_POINT
if [ $? -ne 0 ]; then
    echo "Ошибка при монтировании Btrfs-раздела $BTRFS_DEVICE."
    exit 1
fi

# Удаление подтома Btrfs
echo "Удаление подтома: $BTRFS_SUBVOLUME"
if sudo btrfs subvolume show $MOUNT_POINT/$BTRFS_SUBVOLUME &>/dev/null; then
    sudo btrfs subvolume delete $MOUNT_POINT/$BTRFS_SUBVOLUME
    if [ $? -eq 0 ]; then
        echo "Подтом $BTRFS_SUBVOLUME успешно удалён."
    else
        echo "Ошибка при удалении подтома $BTRFS_SUBVOLUME."
        sudo umount $MOUNT_POINT
        exit 1
    fi
else
    echo "Подтом $BTRFS_SUBVOLUME не найден."
fi

# Отмонтирование Btrfs-раздела
echo "Отмонтирование Btrfs-раздела: $BTRFS_DEVICE"
sudo umount $MOUNT_POINT
if [ $? -eq 0 ]; then
    echo "Btrfs-раздел $BTRFS_DEVICE успешно отмонтирован."
else
    echo "Ошибка при отмонтировании Btrfs-раздела $BTRFS_DEVICE."
    exit 1
fi

echo "Операции завершены."
