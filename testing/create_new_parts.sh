#!/bin/bash

# Создание разделов на диске /dev/sda
parted -a optimal /dev/sda mklabel gpt

# Создание разделов с использованием оптимального выравнивания
parted -a optimal /dev/sda mkpart primary fat32 1MiB 350MiB   # /dev/sda1 - EFI 350 MB
parted -a optimal /dev/sda mkpart primary 350MiB 20.35GiB    # /dev/sda2 - для LUKS с LVM внутри 20 GB
parted -a optimal /dev/sda mkpart primary 20.35GiB 50.35GiB   # /dev/sda3 - для LVM 30 GB
parted -a optimal /dev/sda mkpart primary 50.35GiB 60.35GiB   # /dev/sda4 - btrfs 10 GB
parted -a optimal /dev/sda mkpart primary 60.35GiB 70.35GiB   # /dev/sda5 - LUKS 10 GB
parted -a optimal /dev/sda mkpart primary 70.35GiB 80.35GiB   # /dev/sda6 - ext4 10 GB

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

# Форматирование разделов
mkfs.fat -F32 /dev/sda1
mkfs.btrfs -f /dev/locked_vg/btrfs_in_locked_lvm
mkfs.btrfs -f /dev/opened_vg/btrfs_in_opened_lvm
mkfs.btrfs -f /dev/mapper/luks_inside_lvm
mkfs.btrfs -f /dev/sda4
mkfs.btrfs -f /dev/mapper/luks_on_sda5
mkfs.ext4 /dev/sda6

# Вывод информации о созданных разделах
echo "Разделы созданы успешно."
