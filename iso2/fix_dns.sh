#!/bin/bash

systemctl stop systemd-resolved
systemctl disable systemd-resolved
#rm /etc/resolv.conf
echo -e "nameserver 8.8.8.8\nnameserver 1.1.1.1" | tee -a /etc/resolv.conf
