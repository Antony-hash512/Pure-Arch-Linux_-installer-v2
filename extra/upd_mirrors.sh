#!/bin/bash
cp /etc/pacman.d/mirrorlist "/etc/pacman.d/mirrorlist$(date +%Y-%m-%d_%H-%M-%S)_$RANDOM.bak"
curl -o /etc/pacman.d/mirrorlist https://archlinux.org/mirrorlist/all/
vim /etc/pacman.d/mirrorlist
