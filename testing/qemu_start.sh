#!/bin/bash

CURRENT_MONTH=$(date +%m)
CURRENT_YEAR=$(date +%Y)
RAM_SIZE=4G
CPU_CORES=4

if [ ! -f [modified]OVMF_VARS.4m.fd ]; then
    cp [original]OVMF_VARS.4m.fd [modified]OVMF_VARS.4m.fd
fi

if [ ! -f [modified]archlinux_vm_disk.qcow2 ]; then
    cp [original]archlinux_vm_disk.qcow2 [modified]archlinux_vm_disk.qcow2
fi

if [ ! -f archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso ]; then
    if ! pacman -Qi aria2 &>/dev/null; then
        sudo pacman -S aria2 --noconfirm
    fi
    if ! pacman -Qi wget &>/dev/null; then
        sudo pacman -S wget --noconfirm
    fi
    if [ -f arch.torrent ]; then
        rm arch.torrent
    fi
    wget https://archlinux.org/releng/releases/${CURRENT_YEAR}.${CURRENT_MONTH}.01/torrent/ -O arch.torrent
    aria2c -i arch.torrent --enable-rpc=false --continue=true
    if [ $? -eq 0 ]; then
        echo "Скачивание завершено успешно!"
        # Удаляем старые образы ISO (кроме текущего)
        for iso_file in archlinux-*.iso; do
            if [ -f "$iso_file" ] && [ "$iso_file" != "archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso" ]; then
                echo "Удаляем старый образ: $iso_file"
                rm "$iso_file"
            fi
        done        
        # Удаляем соответствующие .aria2 файлы
        for aria2_file in archlinux-*.iso.aria2; do
            if [ -f "$aria2_file" ] && [ "$aria2_file" != "archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso.aria2" ]; then
                echo "Удаляем файл aria2: $aria2_file"
                rm "$aria2_file"
            fi
        done
    else
        echo "Произошла ошибка при скачивании."
        exit 1
    fi
fi

if ! pacman -Qi qemu-base &>/dev/null; then
    sudo pacman -S qemu-base --noconfirm
fi

qemu-system-x86_64 \
    -enable-kvm \
    -m ${RAM_SIZE} \
    -cpu host \
    -smp ${CPU_CORES} \
    -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=[modified]OVMF_VARS.4m.fd \
    -drive file=[modified]archlinux_vm_disk.qcow2,format=qcow2 \
    -virtfs local,path=../,mount_tag=inst_scripts,security_model=none \
    -virtfs local,path=../cache-repo/,mount_tag=pkgcache,security_model=none \
    -cdrom archlinux-${CURRENT_YEAR}.${CURRENT_MONTH}.01-x86_64.iso \
    -drive file=./mntfld.iso,media=cdrom \
    -boot order=d \
    -netdev user,id=mynet0 \
    -device virtio-net-pci,netdev=mynet0 \
    -display gtk,zoom-to-fit=off \
    -device virtio-vga,edid=on,xres=1280,yres=720 \

    #-audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native \
    #-device intel-hda \
    #-device hda-duplex,audiodev=pa

