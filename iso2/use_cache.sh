#!/bin/bash

mount -t 9p -o trans=virtio pkgcache /var/cache/pacman/pkg \
    && echo "pkgcache подключён" \
    || { echo "Ошибка монтирования pkgcache" >&2 }

ls /var/cache/pacman/pkg
