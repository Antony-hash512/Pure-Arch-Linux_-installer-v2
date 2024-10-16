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



# Удаляем подтома Btrfs

echo "Удаляем подтома Btrfs..."
for subvol in "${BTRFS_SUBVOLUMES[@]}"; do
    echo "Удаляем подтом: $subvol"
    btrfs subvolume delete "${BTRFS_PARTITION}/$subvol"
    if [ $? -ne 0 ]; then
        echo "Ошибка при удалении подтома: $subvol" >&2
        exit 1
    fi
done

echo "Подтома Btrfs успешно удалены."

# Завершение работы
echo "Удаление системы завершено."
read -p "Нажмите Enter для выхода..."
