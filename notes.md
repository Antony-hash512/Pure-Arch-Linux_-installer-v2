```bash
lsblk -l -o NAME,MOUNTPOINTS
``` 
ключ -l уберает древовидное отбражение, ключ -o отображает только определённые поля


```bash
sudo btrfs subvolume list / | grep 'level 5 path'
``` 
вывести список только осоновных сабволюмов

```bash
findmnt /dev/vgname/lvname
```
посмотреть точки доступа