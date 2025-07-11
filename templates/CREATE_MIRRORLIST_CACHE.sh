#!/bin/bash
#root checking
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi
SYSTEM_MIRRORLIST_FILE="/etc/pacman.d/mirrorlist"
CACHE_MIRRORLIST_FILE="reflector_mirrorlist_cache"

#You can use the nearest mirrors to your location
#reflector --country Germany,Netherlands --latest 10 --protocol https --download-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist
if ! pacman -Qi reflector &>/dev/null; then
    sudo pacman -S reflector --noconfirm
fi
reflector --latest 20 --protocol https --download-timeout 10 --sort rate --save $CACHE_MIRRORLIST_FILE
