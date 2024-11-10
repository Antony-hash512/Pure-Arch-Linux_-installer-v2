#!/bin/bash

if ! pacman -Qi pacserve &>/dev/null; then
    sudo pacman -S pacserve
fi

sudo systemctl start pacserve

sudo systemctl start pacserve-ports.service