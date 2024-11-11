#!/bin/bash
# Данный скрипт приспособлен для нескольких LVM-разделов и подтомов Btrfs

# Служебный каталог для монтирования томов Btrfs, добавляем текущую дату и время для уникальности
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
#     ["/dev/mainvg/gigabox"]="@arch_system" "@home_system"
#     ["/dev/nvme0n1p9"]="@arch_system_boot"
# )

# Определение томов lvm для удаления
LVM_VOLUMES=("/dev/mainvg/arch_system" "/dev/mainvg/home_system")

# Определение сабволюмов btrfs для удаления
# Ассоциативный массив, где ключ — это устройство, а значение — массив с именами подтомов
declare -A BTRFS_SUBVOLUMES
BTRFS_SUBVOLUMES=(
    ["/dev/mainvg/gigabox"]="@arch_system @home_system"
)

EFI_NOTE_TO_DELETE=""

# Функция рекурсивного удаления подтомов
delete_subvolumes_recursively() {
    local subvol_path="$1"

    # Проверяем существование подтома перед удалением
    if sudo btrfs subvolume show "$subvol_path" &>/dev/null; then
        # Получаем список всех вложенных подтомов, сортируя их по длине пути в обратном порядке (самые глубокие сначала)
        sudo btrfs subvolume list -o "$subvol_path" --sort=-path | while read -r line; do
            # Извлекаем путь к подтомам
            path=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print $0}' | sed 's/^ *//')
            full_path="$MOUNT_POINT/$path"
            echo "Удаляем подтом: $full_path"
            sudo btrfs subvolume delete "$full_path"
            if [ $? -ne 0 ]; then
                echo "Ошибка при удалении подтома: $full_path" >&2
            fi
        done

        # Удаляем главный подтом
        if [ -d "$subvol_path" ]; then
            echo "Удаляем подтом: $subvol_path"
            sudo btrfs subvolume delete "$subvol_path"
            if [ $? -ne 0 ]; then
                echo "Ошибка при удалении подтома: $subvol_path" >&2
            fi
        fi
    else
        echo "Подтом $subvol_path не найден. Пропуск."
    fi
}

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

# Удаляем подтомы Btrfs
echo "Удаляем подтомы Btrfs..."
for device in "${!BTRFS_SUBVOLUMES[@]}"; do

    read -r -a subvolumes <<< "${BTRFS_SUBVOLUMES[$device]}"

    echo "Монтируем $device в $MOUNT_POINT"
    sudo mount "$device" "$MOUNT_POINT"
    if [ $? -ne 0 ]; then
        echo "Ошибка при монтировании устройства $device." >&2
        exit 1
    fi

    for subvol in "${subvolumes[@]}"; do
        subvol_path="$MOUNT_POINT/$subvol"
        echo "Удаляем подтом: $subvol"
        delete_subvolumes_recursively "$subvol_path"
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
    # Ищем BootNum по имени
    bootnum=$(sudo efibootmgr | grep -Ei "Boot[0-9a-fA-F]{4}.*$EFI_NOTE_TO_DELETE" | head -n1 | sed -n 's/^Boot\([0-9a-fA-F]\{4\}\)\*.*/\1/p')
    if [ -n "$bootnum" ]; then
        echo "Найден BootNum: $bootnum для записи $EFI_NOTE_TO_DELETE"
        sudo efibootmgr -b "$bootnum" -B
        if [ $? -ne 0 ]; then
            echo "Ошибка при удалении записи EFI: $EFI_NOTE_TO_DELETE." >&2
        else
            echo "Запись EFI $EFI_NOTE_TO_DELETE успешно удалена."
        fi
    else
        echo "Запись EFI с именем $EFI_NOTE_TO_DELETE не найдена."
    fi
fi

echo "Удаление системы завершено."
read -p "Нажмите Enter для выхода..."

