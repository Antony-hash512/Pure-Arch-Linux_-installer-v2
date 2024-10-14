#!/bin/bash

# Двумерный массив на основе одномерного
declare -A new_mount_points

# Количество точек монтирования для нового раздела (кроме swap)
new_mount_points_number=2
new_mount_points[0,0]="/"
new_mount_points[0,1]="new_subvol_in_btrfs_in_lvm"
new_mount_points[0,2]="none_in_none"
new_mount_points[0,3]="@arch_system_test42_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"

new_mount_points[1,0]="/home"
new_mount_points[1,1]="new_subvol_in_btrfs_in_lvm"
new_mount_points[1,2]="none_in_none"
new_mount_points[1,3]="@arch_openhome_in_/dev/mainvg/gigabox_in_/dev/nvme0n1p8"

# Вывод элементов двумерного массива
for (( i=0; i<$mount_points_number; i++ )); do
    printf "%d. \n " "$i+1"
    printf "Точка монтирования: %s \n" "${mount_points[$i,0]}"
    printf "Тип размещения раздела: %s \n" "${mount_points[$i,1]}"
    printf "Тип шифрования: %s \n" "${mount_points[$i,2]}"
done


read EMPTY
