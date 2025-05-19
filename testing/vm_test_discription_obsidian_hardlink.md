#pure_arch_linux

[[Arch Linux Installer v2]]

## разметка
```
sda                                                
├─sda1                                             FD65-F97C
├─sda2                                             7fbfe88c-a81d-40c4-9d7c-1c3e1adbd167
│ └─luks_on_sda2                                   tfc66E-cnrD-3V2V-sHKg-MDGr-9yvT-GHeCcc
│   └─locked_vg-btrfs_in_locked_lvm                2dc5c011-6739-456a-88a5-5a2c7075b076
├─sda3                                             avcFhY-Z9qW-f1Oc-HoRW-sk9B-VckD-fyeyfn
│ ├─opened_vg-btrfs_in_opened_lvm                  4aba42d2-db82-49f5-a1ac-efd35d85d97d
│ └─opened_vg-luks_in_opened_lvm                   1eb58acd-e999-489f-a592-5fc8815bc037
│   └─luks_inside_lvm                              a742f7f7-e6a3-4f74-b05c-87f836510256
├─sda4                                             5a684c53-53cd-4419-b7b1-04ea97ba09d3
├─sda5                                             f0ecf279-3df6-43e1-b508-0075960299f2
│ └─luks_on_sda5                                   e26d96e5-d4b6-4022-8edd-4aa04113fbd4
├─sda6                                             7e4a08f1-cde8-4f97-aef0-2645e2691f2f
├─sda7                                             d8526a70-78a1-40a9-b138-90a248ee6ef6
│ └─luks_on_sda7                                   jYP8jX-rWH0-W4TW-leDw-TtHJ-d0xf-643Kb1
│   └─double_locked_vg-btrfs_in_double_locked_lvm  cf6f9731-377c-49cf-b427-538427d76609
└─sda8                                             d7cf1e1f-e766-4dc1-8110-744c6b9caea1
  └─luks_on_sda8                                   gHy8mS-0j4d-lL8P-MJv7-JOw2-EfDm-kiXkSU
    └─double_locked_vg-btrfs_in_double_locked_lvm  cf6f9731-377c-49cf-b427-538427d76609
sr0                                                2025-03-13-19-41-48-00
sr1                                                2025-03-01-17-40-22-00
```



## тестирование предпросмотра

### Пароли от luks'ов:
123 и   YES (в test 9 и 10)

### test1

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_subvol_in_btrfs_in_lvm</way>
		<crypt_mode>none_in_pwd</crypt_mode>
		<lv-volume>/dev/locked_vg/btrfs_in_locked_lvm</lv-volume>
		<subvolume>@arch</subvolume>
		<pv-volumes-uuids>7fbfe88c-a81d-40c4-9d7c-1c3e1adbd167</pv-volumes-uuids>
	</point>
</mountpoints>

```

####  описание 
здесь внутри LUKS находится pv lvm ожидается, что Luks откроется на начальном этапе работы скрипта и всё сработает как если бы шифрования не было,
но этого почему то не происходит
вероятно проблеме скорее всего в функции fill_in_array_by_new_btrfs_subvolumes_for_device как мне подсказал аи, потому что test2 аналогично pv lvm находится внутри LUKS, только там создаётся не сабволюм на уже готовой btrfs, а новый логический том с  ext4 и всё отрабатывает норм при том же режиме шифрования

#### решение проблемы

проверки в функции действительно были лишними, но ключевая проблема была не в них, а в регексе, который убирал пробелы для правильного разбиения на слова.
В обновлённом виде:
```bash
line=$(echo "$line" | sed -E 's/│ +/│·/g')
```
он предусматривает случае, когда между вертикальными чертами не один, а несколько пробелов

#### решение проблемы 2
добавлен код:
```bash
    # Деактивируем LVM-группы и тома, связанные с открытыми крипто-контейнерами
    for device in "${!OPENED_CRYPT_CONTAINERS[@]}"; do
        mapper_name=${OPENED_CRYPT_CONTAINERS[$device]}
        mapper_path="/dev/mapper/$mapper_name"
        vg_names=$(safe_pvs "$mapper_path" --noheadings -o vg_name 2>/dev/null | tr -d ' ')
        if [ -n "$vg_names" ]; then
            for vg in $vg_names; do
                echo -e "${GRAY}Деактивируем VG $vg для $mapper_path${NC}"
                vgchange -an "$vg" || echo -e "${YELLOW}Не удалось деактивировать VG $vg${NC}"
            done
        fi
    done
```
в функцию cleanup_all 

это также решило аналогичную проблему в test2, в test4 ничего не сломано
### test2

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>none_in_pwd</crypt_mode>
		<lv-volume>/dev/locked_vg/new_ext4_from_test2</lv-volume>
		<size>5G</size>
		<pv-volumes-uuids>7fbfe88c-a81d-40c4-9d7c-1c3e1adbd167</pv-volumes-uuids>
	</point>
</mountpoints>

```

#### описание

здесь аналогично первому тесту pv lvm находится внутри LUKS, который открывается на начальном этапе работы скрипта, тут предпросмотр срабатывает нормально 

### test3
#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_subvol_in_btrfs_in_lvm</way>
		<crypt_mode>none_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/btrfs_in_opened_lvm</lv-volume>
		<subvolume>@arch</subvolume>
	</point>
</mountpoints>

```

#### описание

новый сабволюм на btrfs внутри lvm, без шифрования, всё работает

### test4

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_subvol_in_btrfs_in_lvm</way>
		<crypt_mode>pwd_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/luks_in_opened_lvm</lv-volume>
		<subvolume>@arch</subvolume>
	</point>
</mountpoints>

```

#### описание
здесь btrfs находится внутри luks в группе томов, pv lvm которой не в luks
предположительно не срабатывает по той же причине, которая описана в test1
нужно проверить в fill_in_array_by_new_btrfs_subvolumes_for_device

#### решение проблемы
см. test1
### test5
#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>pwd_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/new_encrypted_ext4_in_open_lvm</lv-volume>
		<size>5G</size>
	</point>
</mountpoints>

```

#### описание
в открытом lvm запланирован к созданию новый luks для размещения нового ext4 внутри, всё отображается нормально
### test6
#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>none_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/new_ext4_in_open_lvm</lv-volume>
		<size>5G</size>
	</point>
</mountpoints>

```

#### описание
в открытом lvm запланирован к созданию открытый том с ext4, всё отображается нормально

### test5a

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>pwd_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/new_encrypted_ext4_in_open_lvm</lv-volume>
		<size>200G</size>
	</point>
</mountpoints>

```

#### описание

это проверка на нехватку свободного места, должна отображаться ошибка, но её нет, буду разбираться с этим после решения проблем с тестами 1 и 4
### test6a

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>none_in_none</crypt_mode>
		<lv-volume>/dev/opened_vg/new_ext4_in_open_lvm</lv-volume>
		<size>200G</size>
	</point>
</mountpoints>

```

## новые тесты предпросмотра

### test7

Форматирование в ext4
sda6                                             7e4a08f1-cde8-4f97-aef0-2645e2691f2f
#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>format_ext4</way>
		<crypt_mode>none</crypt_mode>
		<uuid>7e4a08f1-cde8-4f97-aef0-2645e2691f2f</uuid>
	</point>
</mountpoints>

```

### test8 
sda6                                             7e4a08f1-cde8-4f97-aef0-2645e2691f2f

Форматирование в luks с ext4

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>format_ext4</way>
		<crypt_mode>pwd</crypt_mode>
		<uuid>7e4a08f1-cde8-4f97-aef0-2645e2691f2f</uuid>
	</point>
</mountpoints>

```

### test9
два pv lvm внутри luks'ов в одной группе
sda7                                             d8526a70-78a1-40a9-b138-90a248ee6ef6
sda8                                             d7cf1e1f-e766-4dc1-8110-744c6b9caea1
новый сабвол на готовой btrfs как было в test1

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_subvol_in_btrfs_in_lvm</way>
		<crypt_mode>none_in_pwd</crypt_mode>
		<lv-volume>/dev/double_locked_vg/btrfs_in_double_locked_lvm</lv-volume>
		<subvolume>@arch</subvolume>
		<pv-volumes-uuids>d8526a70-78a1-40a9-b138-90a248ee6ef6,d7cf1e1f-e766-4dc1-8110-744c6b9caea1</pv-volumes-uuids>
	</point>
</mountpoints>

```

### test10
два pv lvm внутри luks'ов в одной группе
sda7                                             d8526a70-78a1-40a9-b138-90a248ee6ef6
sda8                                             d7cf1e1f-e766-4dc1-8110-744c6b9caea1
новый ext4 как было в test2

#### код
```xml
<mountpoints>
	<point type="new">
		<location>/</location>
		<way>new_ext4_in_lvm</way>
		<crypt_mode>none_in_pwd</crypt_mode>
		<lv-volume>/dev/double_locked_vg/new_ext4_in_double_luksed_pvs</lv-volume>
		<size>5G</size>
		<pv-volumes-uuids>d8526a70-78a1-40a9-b138-90a248ee6ef6,d7cf1e1f-e766-4dc1-8110-744c6b9caea1</pv-volumes-uuids>
	</point>
</mountpoints>

```

