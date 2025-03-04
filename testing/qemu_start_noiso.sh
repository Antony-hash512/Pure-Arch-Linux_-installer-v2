#!/bin/bash

qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -cpu host \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file=/home/share/data/extra/vm_disks/edk2/2024/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=/home/share/data/extra/vm_disks/edk2/2024/OVMF_VARS.4m.fd \
    -drive file=/home/share/data/extra/vm_disks/archlinux_vm_disk.qcow2,format=qcow2 \
    -nic user,model=virtio-net-pci \
    -vga virtio
