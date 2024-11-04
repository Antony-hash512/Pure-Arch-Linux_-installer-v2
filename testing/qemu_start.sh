#!/bin/bash

qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -cpu host \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
    -drive file=/home/mega/data/extra/vm_disks/archlinux_vm_disk.qcow2,format=qcow2 \
    -virtfs local,path=/home/mega/git/Pure-Arch-Linux_-installer-v2/,mount_tag=inst_scripts,security_model=none \
    -cdrom /home/mega/data/extra/torrents/archlinux-2024.11.01-x86_64.iso \
    -drive file=../mntfld.iso,media=cdrom \
    -boot order=d \
    -nic user,model=virtio-net-pci \
    -vga virtio
