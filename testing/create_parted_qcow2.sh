#!/bin/bash

SIZE=120

./create_blank_qcow2.sh ${SIZE}G.qcow2 $SIZE

if [ -f '[modified]archlinux_vm_disk.qcow2' ]; then
    read -p "сделать резервную копию '[modified]archlinux_vm_disk.qcow2' (y/n)? " response
    if [[ "$response" =~ [nNНн] ]]; then
        rm -f '[modified]archlinux_vm_disk.qcow2'
    else
        mv '[modified]archlinux_vm_disk.qcow2' '[modified_backup]archlinux_vm_disk.qcow2'
    fi
fi
if [ -f '[original]archlinux_vm_disk.qcow2' ]; then
    read -p "сделать резервную копию '[original]archlinux_vm_disk.qcow2' (y/n)? " response
    if [[ "$response" =~ [nNНн] ]]; then
        rm -f '[original]archlinux_vm_disk.qcow2'
    else
        mv '[original]archlinux_vm_disk.qcow2' '[original_backup]archlinux_vm_disk.qcow2'
    fi
fi

echo "на виртульной машине qemu выполните следующие команды:"
echo "mkdir /mnt/sr0"
echo "mount /dev/sr0 /mnt/sr0"
echo "cd /mnt/sr0"
echo "./create_default_parted_gpt.sh"
echo "poweroff"
./qemu_start.sh --alt-disk ${SIZE}G.qcow2


mv ${SIZE}G.qcow2 '[original]archlinux_vm_disk.qcow2'
