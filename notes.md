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

``` bash
sed -i '1s/^/INSTALL_INFO\n/' $LSBLK_RAW_INFO
```
в певую строку файла дописываем текст "INSTALL_INFO"

```bash
sudo vgs -o ljdlfj
```
получить справку о все доступных параметрах