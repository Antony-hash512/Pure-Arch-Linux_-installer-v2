```bash
sudo pacman -S edk2-ovmf
```
установка пакета для имитации UEFI на Qemu

```bash
cp /usr/share/edk2-ovmf/x64/OVMF_VARS.fd .
```

```bash
cp /usr/share/edk2-ovmf/x64/OVMF_VARS.fd /home/mega/data/extra/vm_disks/
```
копируем изменяемую часть виртульной UEFI чтобы избежать повреждения оригинала
или в случае восстановления из резервной копии

