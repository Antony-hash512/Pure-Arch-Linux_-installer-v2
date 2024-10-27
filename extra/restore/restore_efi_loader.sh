#!/bin/bash

setfont cyr-sun16

lsblk

# Задайте переменные для разделов и загрузчика
read -p "Корневой раздел (например /dev/nvme0n1p6):" ROOT_PART
read -p "EFI-раздел: (например /dev/nvme0n1p1):" EFI_PART
read -p "Идентификатор загрузчика: (например PureArch):" BOOTLOADER_ID

MNT_DIR="/mnt/rootdir_$(date +%s)_$RANDOM"

mkdir -p $MNT_DIR

# Монтируем корневой раздел
echo "Монтирование корневого раздела Arch Linux..."
if ! mount $ROOT_PART $MNT_DIR; then
  echo "Ошибка: не удалось смонтировать корневой раздел" >&2
  exit 1
fi

# Монтируем EFI-раздел
echo "Монтирование EFI-раздела..."
mkdir -p $MNT_DIR/boot/efi
if ! mount $EFI_PART $MNT_DIR/boot/efi; then
  echo "Ошибка: не удалось смонтировать EFI-раздел" >&2
  exit 1
fi

# Проверяем, что разделы смонтированы
echo "Смонтированные файловые системы:"
findmnt $MNT_DIR

# Входим в окружение Arch Linux через chroot и выполняем восстановление GRUB
echo "Выполняем восстановление GRUB через arch-chroot..."
arch-chroot $MNT_DIR /bin/bash -c "
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=$BOOTLOADER_ID --recheck;
  grub-mkconfig -o /boot/grub/grub.cfg
"

# Завершаем работу
echo "Восстановление завершено. Размонтируем файловые системы..."

# Добавляем sync для записи данных
sync

# Размонтируем системные каталоги и разделы
umount $MNT_DIR/boot/efi
umount $MNT_DIR

echo "Загрузчик GRUB успешно восстановлен. Перезагрузите систему."
