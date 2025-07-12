#!/bin/bash
cp [original]archlinux_vm_disk.qcow2 [modified]archlinux_vm_disk.qcow2
cp [original]OVMF_VARS.4m.fd [modified]OVMF_VARS.4m.fd
./qemu_start.sh
