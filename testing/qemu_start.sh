#!/bin/bash

qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -cpu host \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file=/home/mega/data/extra/vm_disks/edk2/2024/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=/home/mega/data/extra/vm_disks/edk2/2024/OVMF_VARS.4m.fd \
    -drive file=/home/mega/data/extra/vm_disks/archlinux_vm_disk.qcow2,format=qcow2 \
    -virtfs local,path=/home/mega/git/Pure-Arch-Linux_-installer-v2/,mount_tag=inst_scripts,security_model=none \
    -virtfs local,path=/home/mega/git/Pure-Arch-Linux_-installer-v2/cash-repo/,mount_tag=pkgcache,security_model=none \
    -cdrom /home/mega/data/extra/torrents/archlinux-2025.03.01-x86_64.iso \
    -drive file=./mntfld.iso,media=cdrom \
    -boot order=d \
    -netdev user,id=mynet0 \
    -device virtio-net-pci,netdev=mynet0 \
    -vga virtio
