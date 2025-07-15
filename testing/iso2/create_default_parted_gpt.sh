#!/bin/bash

# устанавливаем кириллический шрифт в консоль
setfont cyr-sun16

#запрашиваем подтверждение на создание новых разделов
echo "Введите PARTING_START если сейчас находитесь на qemu и хотите разметить пустой диск"
echo "Будьте осторожны, никогда не используйте этот скрипт на хосте"
echo "он предназначен только запуска внутри qemu, чтобы разметить пустой диск"
read -r response
if [[ ! "$response" == "PARTING_START" ]]; then
    echo "Выход без создания новых разделов."
    exit 0
fi

# для /dev/sda5 btrfs внутри luks
# имеется неоднозначность, при использовании uuid именно файловой системы,
# а не раздела т.к. uuid luks это f0ecf279-3df6-43e1-b508-0075960299f2, а
# uuid btrfs внутри это e26d96e5-d4b6-4022-8edd-4aa04113fbd4
# я думаю при использовании uuid файловой системы вместо partuuid,
# идентификацию нужно проводить именно по uuid luks'а
#btrfs как содержимое контейнера будет идентифицироваться
#по блочному устройству /dev/mapper/luks-f0ecf279-3df6-43e1-b508-0075960299f2,
# а не по uuid файловой системы
# поскольку uuid файловой системы для mkfs.btrfs -f /dev/mapper/luks_on_sda5
# я не задаю, он будет заменён на произвольный


# Создание разделов на диске /dev/sda
parted -s -a optimal /dev/sda mklabel gpt

# Создание разделов с использованием оптимального выравнивания
parted -s -a optimal /dev/sda mkpart ESP fat32 1MiB 350MiB   # /dev/sda1 - EFI 350 MB
parted -s -a optimal /dev/sda mkpart primary 350MiB 20GiB    # /dev/sda2 - для LUKS с LVM внутри 20 GB
parted -s -a optimal /dev/sda mkpart primary 20GiB 50GiB   # /dev/sda3 - для LVM 30 GB
parted -s -a optimal /dev/sda mkpart primary 50GiB 60GiB   # /dev/sda4 - btrfs 10 GB
parted -s -a optimal /dev/sda mkpart primary 60GiB 70GiB   # /dev/sda5 - LUKS 10 GB
parted -s -a optimal /dev/sda mkpart primary 70GiB 80GiB   # /dev/sda6 - ext4 10 GB
parted -s -a optimal /dev/sda mkpart primary 80GiB 85GiB   # /dev/sda7 - 1й pv для lvm
parted -s -a optimal /dev/sda mkpart primary 85GiB 90GiB  # /dev/sda8 - 2й pv для lvm

# Задаём фиксированные PARTUUID для разделов
sgdisk --partition-guid=1:e8db4848-b418-42b6-a19a-272cbd1259db /dev/sda # EFI
sgdisk --partition-guid=2:309f026b-2f3a-4b81-93f3-91f01b2bd264 /dev/sda # LUKS
sgdisk --partition-guid=3:c64c4dae-e095-43f4-852c-079a71e09da9 /dev/sda # не потребуется, LVM2_member
sgdisk --partition-guid=4:25b07408-5287-442b-b301-cd13d70fcd7a /dev/sda # btrfs
sgdisk --partition-guid=5:459c5d86-02c1-4b60-9536-eefbb37b93cf /dev/sda # LUKS
sgdisk --partition-guid=6:e6b3a93f-4a9a-4bed-a986-fed780600a20 /dev/sda # ext4
sgdisk --partition-guid=7:6dc4628a-4ea8-4686-ba68-4a15801d00d5 /dev/sda # LUKS
sgdisk --partition-guid=8:6afde44f-0917-4ef0-bd18-70e31737278d /dev/sda # LUKS

# шпаргалка по uuid файловых систем и LUKS:
# FD65-F97C - /dev/sda1 - EFI
# 7fbfe88c-a81d-40c4-9d7c-1c3e1adbd167 - /dev/sda2 - LUKS внутри которого lvm
# --changeable -- /dev/sda3 - не потребуется, LVM2_member
# 5a684c53-53cd-4419-b7b1-04ea97ba09d3 - /dev/sda4 - btrfs
# f0ecf279-3df6-43e1-b508-0075960299f2 - /dev/sda5 - LUKS внутри которого btrfs
# 7e4a08f1-cde8-4f97-aef0-2645e2691f2f - /dev/sda6 - ext4
# d8526a70-78a1-40a9-b138-90a248ee6ef6 - /dev/sda7 - LUKS внутри которого lvm с 2мя pv
# d7cf1e1f-e766-4dc1-8110-744c6b9caea1 - /dev/sda8 - LUKS внутри которого lvm с 2мя pv

# Установка флага загрузки для EFI раздела
parted -s /dev/sda set 1 boot on
parted -s /dev/sda set 1 esp on

# Создание LUKS на /dev/sda2
cryptsetup luksFormat --align-payload=8192 --uuid=7fbfe88c-a81d-40c4-9d7c-1c3e1adbd167 /dev/sda2
cryptsetup open /dev/sda2 luks_on_sda2

# Создание физического тома LVM внутри LUKS на /dev/sda2
pvcreate --dataalignment 1m /dev/mapper/luks_on_sda2
vgcreate locked_vg /dev/mapper/luks_on_sda2
lvcreate -n btrfs_in_locked_lvm -L 10G locked_vg

# Создание физического тома и группы томов для /dev/sda3
pvcreate --dataalignment 1m /dev/sda3
vgcreate opened_vg /dev/sda3

# Создание логических томов в opened_vg
lvcreate -n btrfs_in_opened_lvm -L 10G opened_vg
lvcreate -n luks_in_opened_lvm -L 10G opened_vg

# Создание LUKS внутри LVM
cryptsetup luksFormat --align-payload=8192 /dev/opened_vg/luks_in_opened_lvm
cryptsetup open /dev/opened_vg/luks_in_opened_lvm luks_inside_lvm

# Создание LUKS на /dev/sda5
cryptsetup luksFormat --align-payload=8192 --uuid=f0ecf279-3df6-43e1-b508-0075960299f2 /dev/sda5
cryptsetup open /dev/sda5 luks_on_sda5

# Создание LUKS на /dev/sda7 и /dev/sda8
cryptsetup luksFormat --align-payload=8192 --uuid=d8526a70-78a1-40a9-b138-90a248ee6ef6 /dev/sda7
cryptsetup open /dev/sda7 luks_on_sda7
cryptsetup luksFormat --align-payload=8192 --uuid=d7cf1e1f-e766-4dc1-8110-744c6b9caea1 /dev/sda8
cryptsetup open /dev/sda8 luks_on_sda8

# Создание физических томов LVM на /dev/sda7 и /dev/sda8
pvcreate --dataalignment 1m /dev/mapper/luks_on_sda7
pvcreate --dataalignment 1m /dev/mapper/luks_on_sda8
vgcreate double_locked_vg /dev/mapper/luks_on_sda7 /dev/mapper/luks_on_sda8
lvcreate -n btrfs_in_double_locked_lvm -L 6G double_locked_vg



# Форматирование разделов
mkfs.fat -F32 -n EFI -i FD65F97C /dev/sda1
mkfs.btrfs -f /dev/locked_vg/btrfs_in_locked_lvm
mkfs.btrfs -f /dev/opened_vg/btrfs_in_opened_lvm
mkfs.btrfs -f /dev/mapper/luks_inside_lvm
mkfs.btrfs -f -U 5a684c53-53cd-4419-b7b1-04ea97ba09d3 /dev/sda4
mkfs.btrfs -f /dev/mapper/luks_on_sda5
mkfs.ext4 -f -U 7e4a08f1-cde8-4f97-aef0-2645e2691f2f /dev/sda6
mkfs.btrfs -f /dev/double_locked_vg/btrfs_in_double_locked_lvm




# Вывод информации о созданных разделах
echo "Разделы созданы успешно."
