#!/bin/bash

qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -cpu host \
    -smp 4 \
    -drive if=pflash,format=raw,readonly=on,file=/home/share/data/extra/vm_disks/edk2/2024/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=/home/share/data/extra/vm_disks/edk2/2024/OVMF_VARS.4m.fd \
    -drive file=/home/share/data/extra/vm_disks/archlinux_vm_disk.qcow2,format=qcow2 \
    -virtfs local,path=/home/share/git/Pure-Arch-Linux_-installer-v2/,mount_tag=inst_scripts,security_model=none \
    -virtfs local,path=/home/share/git/Pure-Arch-Linux_-installer-v2/cash-repo/,mount_tag=pkgcache,security_model=none \
    -cdrom /home/share/data/extra/torrents/archlinux-2025.05.01-x86_64.iso \
    -drive file=./mntfld.iso,media=cdrom \
    -boot order=d \
    -netdev user,id=mynet0 \
    -device virtio-net-pci,netdev=mynet0 \
    -display gtk,zoom-to-fit=off \
    -vga virtio -device virtio-vga,edid=on,xres=1280,yres=720 \
    #-audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native \
    #-device intel-hda \
   # -device hda-duplex,audiodev=pa

