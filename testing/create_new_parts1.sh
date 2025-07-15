#!/bin/bash

#запрашиваем подтверждение на создание новых разделов
echo "Введите PARTING_START если сейчас находитесь на qemu и хотите разметить пустой диск"
read -r response
if [[ ! "$response" == "PARTING_START" ]]; then
    echo "Выход без создания новых разделов."
    exit 0
fi



# Создание разделов на диске /dev/sda
parted -a optimal /dev/sda mklabel gpt

# Создание разделов с использованием оптимального выравнивания
parted -a optimal /dev/sda mkpart primary fat32 1MiB 350MiB   # /dev/sda1 - EFI 350 MB
parted -a optimal /dev/sda mkpart primary 350MiB 20GiB    # /dev/sda2 - для LUKS с LVM внутри 20 GB
parted -a optimal /dev/sda mkpart primary 20GiB 50GiB   # /dev/sda3 - для LVM 30 GB
parted -a optimal /dev/sda mkpart primary 50GiB 60GiB   # /dev/sda4 - btrfs 10 GB
parted -a optimal /dev/sda mkpart primary 60GiB 70GiB   # /dev/sda5 - LUKS 10 GB
parted -a optimal /dev/sda mkpart primary 70GiB 80GiB   # /dev/sda6 - ext4 10 GB
parted -a optimal /dev/sda mkpart primary 80GiB 85GiB   # /dev/sda7 - 1й pv для lvm
parted -a optimal /dev/sda mkpart primary 85GiB 90GiB  # /dev/sda8 - 2й pv для lvm


# Установка флага загрузки для EFI раздела
parted /dev/sda set 1 boot on

# Создание LUKS на /dev/sda2
cryptsetup luksFormat --align-payload=8192 /dev/sda2
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
cryptsetup luksFormat --align-payload=8192 /dev/sda5
cryptsetup open /dev/sda5 luks_on_sda5

# Создание LUKS на /dev/sda7 и /dev/sda8
cryptsetup luksFormat --align-payload=8192 /dev/sda7
cryptsetup luksFormat --align-payload=8192 /dev/sda8
cryptsetup open /dev/sda7 luks_on_sda7
cryptsetup open /dev/sda8 luks_on_sda8

# Создание физических томов LVM на /dev/sda7 и /dev/sda8
pvcreate --dataalignment 1m /dev/mapper/luks_on_sda7
pvcreate --dataalignment 1m /dev/mapper/luks_on_sda8
vgcreate double_locked_vg /dev/mapper/luks_on_sda7 /dev/mapper/luks_on_sda8
lvcreate -n btrfs_in_double_locked_lvm -L 6G double_locked_vg



# Форматирование разделов
mkfs.fat -F32 /dev/sda1
mkfs.btrfs -f /dev/locked_vg/btrfs_in_locked_lvm
mkfs.btrfs -f /dev/opened_vg/btrfs_in_opened_lvm
mkfs.btrfs -f /dev/mapper/luks_inside_lvm
mkfs.btrfs -f /dev/sda4
mkfs.btrfs -f /dev/mapper/luks_on_sda5
mkfs.ext4 /dev/sda6
mkfs.btrfs -f /dev/double_locked_vg/btrfs_in_double_locked_lvm

# Вывод информации о созданных разделах
echo "Разделы созданы успешно."
