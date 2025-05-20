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

```bash
 sudo lvs mainvg --noheading -o lv_name
```
получить все логические тома в указанной группе

```bash
name=${current_row["name"]}
#преобразуем строку name в массив с разделителем "_in_"
read -r -a names <<< "${name//_in_/ }"
```
преобразуем строку name в массив с разделителем "_in_"
данная реализация будет отовсюду выпилина поскольку я перешёл на новый формат xml-файла

#определяем длину строки в файле:
```bash
LENGTH_OF_LINE_IN_LSBLK_RAW_INFO=$(wc -L < $LSBLK_RAW_INFO)
```

```bash
# Определяем количество массивов вида new_pointX автоматически
ALL_NEW_POINTS=()
for var in $(compgen -A variable | grep -E '^new_point[0-9]+$'); do
    ALL_NEW_POINTS+=("$var")
done

ALL_EXTRA_POINTS=()
for var in $(compgen -A variable | grep -E '^extra_point[0-9]+$'); do
    ALL_EXTRA_POINTS+=("$var")
done
```