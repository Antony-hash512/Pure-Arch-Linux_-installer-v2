#!/bin/bash

# Установка переменных
LVM_VOLUME="/dev/mainvg/mining_randomx"
BTRFS_DEVICE="/dev/nvme0n1p9"
BTRFS_SUBVOLUME="@mining_randomx_boot"
MOUNT_POINT="/mnt/btrfs_mount"

# Удаление LVM тома
echo "Удаление LVM тома: $LVM_VOLUME"
if lvdisplay $LVM_VOLUME &>/dev/null; then
    sudo lvremove -y $LVM_VOLUME
    if [ $? -eq 0 ]; then
        echo "LVM том $LVM_VOLUME успешно удалён."
    else
        echo "Ошибка при удалении LVM тома $LVM_VOLUME."
        exit 1
    fi
else
    echo "LVM том $LVM_VOLUME не найден."
fi

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
