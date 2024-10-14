#!/bin/bash
#!/bin/bash

# Проверка версии Bash
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    printf "Требуется Bash версии 4.0 или выше. Текущая версия: %s\n" "${BASH_VERSION}" >&2
    exit 1
fi

# Если версия Bash подходит, продолжаем выполнение скрипта
printf "Bash версии %s.\n" "${BASH_VERSION}"



# Этот скрипт предназначен для автоматической установки Arch Linux планируется сделать его универсальным

# Убедитесь, что вы выполняете этот скрипт от имени суперпользователя (root)

# установка переменых с логической смысловой нагрузкой
#пока скрип планируется использовать только для UEFI, поддержка legacy будет добавлена потом

# откуда устанавливается система
INSTALL_FROM="other_arch_system" # other_arch_system - с уже установленного Арча, iso - с LiveCD/DVD/USB
# эта опция влияет на омонтирования EFI-раздела и обратного примонтирования его

# Для списка разделов, которые нужно будет создать будем использовать массивы
# Своп будет настраватся отдельно: опция для него:
# Думаю не стоит реализовывать т.к. своп можно настроить уже после установки, но если будет свободное время, то можно
# 1) не использовать 2) прописать в fstab уже существующий  3) создать новый внутри lvm  4) создать новый в указанном разделе (осторожно) 5) создать новый ввиде файла (пока не буду реализовывать)
# Каждый элемент массива должен обязательно включать в себя следующую инфу:
# сначала будут перечислены ситуации, которые могут понадобится лично мне, остальные возможно будут добавлены потому
# 0) точка монтирования
# 1) Тип расположения точки монирования: уже созданый отдельный раздел для форматирования в ext4(зашифровать?), создать сабволюм на уже созданом btrfs(зашифрован?), создать сабволюм на уже созданом btrfs(зашифрован?) внутри уже созданного lvm(зашифрован?), создать том ext4(зашифровать?) в уже созданом lvm(зашифрован?)
# возможные значения: format_ext4, new_subvol_in_btrfs, new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm
# возможные значение для инфы о шифровании: (для format_ext4, new_subvol_in_btrfs): none, key, file, (для new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm): none_in_none, none_in_key, none_in_file, key_in_none, file_in_none (случаи двойного шифорования не рассматриваем из-за избыточности такого действия), key или file - какой метод расшифровки будет использован при загрузке системы?
# если выбран ключ, то путь к нему нужно указать вручную в ходе выполнения скрипта, в данный момент будет считать так
# 2) название тома и/или раздела (для вложенной структуры нужно использовать разделение "_in_" например: @arch_system42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8)
# 3) указываем путь ключу, если его нужно создать или использовать уже готовый для расшифровки

# Объявление ассоциативного массива для имитации вложенного массива
declare -A new_mount_points
nested_array[0]="/ new_subvol_in_btrfs_in_lvm none_in_none @arch_system_test42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"
nested_array[1]="/home new_subvol_in_btrfs_in_lvm none_in_none @arch_openhome_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"


#Второй список содержит список уже созданых разделов, которые нужно просто смонтировать и прописать в fstab
#вводим в таком же формате: 0) точка монтирования, 1) тип расположения 2) название раздела(+ сабволюма, тома) 3) путь ключу (если используется ключ)  


# Часть данных устарело но пока не буду удалять пока всё не переделаю
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
