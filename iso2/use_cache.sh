#!/bin/bash

mount -t 9p -o trans=virtio pkgcache /var/cache/pacman/pkg

ls /var/cache/pacman/pkg
