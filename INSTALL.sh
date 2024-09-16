#!/bin/bash

# Этот скрипт предназначен для автоматической установки Arch Linux на зашифрованный LVM том в существующей группе томов

# Убедитесь, что вы выполняете этот скрипт от имени суперпользователя (root)

# Установка переменных
VG_NAME="mainvg"  # Укажите имя существующей группы томов
LV_ROOT="mining_randomx"  # Имя логического тома для корня
EFI_DEV="/dev/nvme0n1p1"
BTRFS_BOOT_DEV="/dev/nvme0n1p9"
BTRFS_BOOT_SUBVOL="@mining_randomx_boot"

ROOT_VOLUME_SIZE="10G"
EXTRA_VOLUME_UUID="5fabedda-b832-4509-af6a-014f56e5e502" # если экстра-раздала с блокчейном монеро нет, то размер в 10G надо изменить на приемлемый

SOFT_PACK2="networkmanager btrfs-progs nano vim mc man-db less htop tmux monero p2pool xmrig ntfs-3g dosfstools lvm2 cryptsetup"


#Обновление времени
timedatectl set-ntp true

echo "test тест"
setfont cyr-sun16
echo "test тест"

# Вывод информации о блочных устройствах
lsblk
echo "указано: EFI: $EFI_DEV, Btrfs-раздел для добавления в него бута: $BTRFS_BOOT_DEV, группа томов LVM: $VG_NAME (всё это должно быть уже созданно)"
echo "то будет создано: $BTRFS_BOOT_SUBVOL - том для бута в btrfs, $LV_ROOT - том в LVM, эти имена должны быть не заняты"
echo "если разделы правильно не подготовлены нажми cltr+C для прерывания скрипта и подготовь разделы"
read EMPTY

#этот шаг нужен, если установка идёт с уже установленной системы
umount /boot/efi

# Скачивание нужных для установки пакетов
pacman -Suy
packages=("arch-install-scripts" "lvm2" "cryptsetup")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done


# Создание новых логических томов
echo "ВНИМАНИЕ! YES нужно будет написать ЗАГЛАВНЫМИ буквами"
lvcreate -L $ROOT_VOLUME_SIZE $VG_NAME -n $LV_ROOT

# Шифрование логических томов
cryptsetup luksFormat /dev/$VG_NAME/$LV_ROOT

# Открытие зашифрованных томов
cryptsetup open /dev/$VG_NAME/$LV_ROOT cryptroot

# Форматирование логических томов
mkfs.ext4 /dev/mapper/cryptroot

# Монтирование файловой системы в /mnt/system_installing
mkdir -p /mnt/system_installing
mount /dev/mapper/cryptroot /mnt/system_installing

# Создание каталогов для будущих монтирований
mkdir -p /mnt/system_installing/boot


# Монтирование Btrfs-раздела и создание подтома для /boot
# (можно пропустить, если подтом уже создан)
mkdir -p /mnt/btrfs
mount $BTRFS_BOOT_DEV /mnt/btrfs
btrfs subvolume create /mnt/btrfs/$BTRFS_BOOT_SUBVOL
umount /mnt/btrfs

# Монтирование подтома для /boot
mount -o subvol=$BTRFS_BOOT_SUBVOL $BTRFS_BOOT_DEV /mnt/system_installing/boot


# Монтирование EFI-раздела
mkdir -p /mnt/system_installing/boot/efi
mount $EFI_DEV /mnt/system_installing/boot/efi

# Установка базовой системы
pacstrap /mnt/system_installing base linux linux-firmware btrfs-progs lvm2 cryptsetup

# Генерация fstab
genfstab -U /mnt/system_installing >> /mnt/system_installing/etc/fstab

mkdir /mnt/system_installing/mnt/extra1
echo "UUID=$EXTRA_VOLUME_UUID	/mnt/extra1    	ext4      	rw,relatime	0 2" >> /mnt/system_installing/etc/fstab

#Настройка зашифрованного раздела
echo "cryptroot UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_ROOT) none luks" > /mnt/system_installing/etc/crypttab

echo "GRUB_CMDLINE_LINUX=\"cryptdevice=/dev/$VG_NAME/$LV_ROOT:cryptroot root=/dev/mapper/cryptroot\"" >> /mnt/system_installing/etc/default/grub



#получение имени каталога
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
#копирование дополнительного скрипта, для выполнения внутри системы (должен быть в одном каталоге с этим)
cp $SCRIPT_DIR/run_inside_chroot.sh /mnt/system_installing
#копирование файла README
cp $SCRIPT_DIR/homefiles.tar.gz /mnt/system_installing


#-------------------------------
# Chroot в новую систему
arch-chroot /mnt/system_installing /bin/bash -c "./run_inside_chroot.sh \"$SOFT_PACK2\""
#-------------------------------


#удаляем выполнившуюся в chroot'е копию второго скрипта
rm /mnt/system_installing/run_inside_chroot.sh 


# Отмонтирование 
umount -R /mnt/system_installing

#только если установка была с уже установленной системы
mount $EFI_DEV /boot/efi

cryptsetup close cryptroot

echo "ALL DONE"

echo "Если загрузчик установлен другим линуксом, не забудь выполнить в нём update-grub (или grub-mkconfig -o /boot/grub/grub.cfg)"

# Перезагрузка
echo "Установка завершена. Перезагрузите компьютер."
