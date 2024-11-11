#!/bin/bash

mkdir /mnt/pkgcache
mount -t 9p -o trans=virtio pkgcache /mnt/pkgcache

ln -s /mnt/pkgcache /var/cache/pacman/pkg
