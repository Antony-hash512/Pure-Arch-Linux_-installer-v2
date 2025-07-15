#!/usr/bin/env bash
# https://github.com/Antony-hash512/Cryptful-Arch-Linux_-installer-v2/
read -r -d '' LOGO <<'EOF'
````````````````````````````````````````````````````
  ______                         ___       _ 
 / _____)                  _    / __)     | |
| /       ____ _   _ ____ | |_ | |__ _   _| |
| |      / ___) | | |  _ \|  _)|  __) | | | |
| \_____| |   | |_| | | | | |__| |  | |_| | |
 \______)_|    \__  | ||_/ \___)_|   \____|_|
              (____/|_|                      
    _             _       _     _                  
   / \   _ __ ___| |__   | |   (_)_ __  _   ___  __
  / _ \ | '__/ __| '_ \  | |   | | '_ \| | | \ \/ /
 / ___ \| | | (__| | | | | |___| | | | | |_| |>  < 
/_/   \_\_|  \___|_| |_| |_____|_|_| |_|\__,_/_/\_\
                                                   
 ___           _        _ _                   ____  
|_ _|_ __  ___| |_ __ _| | | ___ _ __  __   _|___ \ 
 | || '_ \/ __| __/ _` | | |/ _ \ '__| \ \ / / __) |
 | || | | \__ \ || (_| | | |  __/ |     \ V / / __/ 
|___|_| |_|___/\__\__,_|_|_|\___|_|      \_(_)_____|
EOF

#0) читаем аргументы командной строки, включаем киррилический шрифт, проверяем на права рута и версию баша
#1) задаём различные переменные и константы, устанавливаем необходимые пакеты
#2) получаем от пользователя данные какие компоненты использовать
#2.1) получаем данные из xml-файла
#2.2) проверяем корректность данных в xml-файле (задача на потом, пока что работаем с заведомо корректними данными)
#3) проходимся по массиву точек монтирования, открываем крипто-контейнеры, в которых уже есть существующая
#структура на этом же этапе обрабатываем некоторые виды ошибок
#4) взяв за основу вывод команды lsblk отображаем пользователя информацию о:
#  * уже существующих поддомах на btrfs
#  * поддома btrfs, которые планируются к созданию (и какая точка мониторования планируется к привязке)
#  * логические тома lvm, которые планируются к созданию (+ точки монирования)
#  * крипто-контейны, luks, которые планируются к созданию и что в них планируется разместить
#  * существующих проблемах, например нехватки свободного места и т.д.
#5) выполняем установку системы после явного подтверждения пользователем

: <<'TODO'
* сделать двух-факторку на гитхабе с бекапом ключа
* удалять кеш рефлектора если ему больше суток
* сделать скрипт для автогенерации размеченного образа диска с нужными uuid
* реализовать поддержку старых ноутбуков с legacy bios
* проверить открытия luksов по кейфайлу (в случаях с ext4 может быть создан новый кейфайл, в случаях с btrfs нет)

* зарелизить бету !!!! <-- ВАЖНО НАКОНЕЦ-ТО НАДО ЗАРЕЛИЗИТЬ ГОТОВЫЙ MVP
* для тегов uuid и pv-volumes-uuids можно ввести параметр type: fs или part (по умолчанию fs)
* написать функцию, для проверки гарантированного свободного места в btrfs томах
* создать функцию, которая будет проверять корректность данных в xml-файле


* добавить в cryptsetup luksAddKey --pbkdf pbkdf2 всем крипо-контейнерам
для возможности расшифровки grub'ом
* добавить возможность шифрования /boot и расшифровки его grub'ом
* автогенерация нужных хуков
* + btrfs с шифрованием, без lvm
* написать более подробную документацию

* не писать в crypttab, дублирующиеся записи
* не затирать настройки груба с дописывать к шаблону настроек (желательно, но не критично)
* добавить проверку хука при установке шифрования до установки системы
* можно добавить опцию автогенерации хуков в настройки
* допилить реализацию softpack_tweaks
* добавить копирование и распакову архивов для root
* брать булевы параметры для рефлектора из xml-файла
* релизовать и протестировать поддержку других систем инициализации на случай установки Artix
* если не передумаю, сделать возможным установку не из Arch-подобных систем с использованием chroot вместо arch-chroot
* если не передумаю, вернуть создание скриптов для автоматического удаления из прошлой версии
    * разобраться что не так с удалением сабволюмов через автоматический скрипт

TODO

# Переменные для обработки некоторых аргументов командной строки
LOG_KEY="--log"
LOG_FILE="log.txt"
VIEW_ONLY_KEY="--view-only"
VIEW_ONLY_FLAG=false
HELP_KEY="--help"
NO_CACHE_MIRRORS="--no-cache-mirrors"
IS_GET_MIRRORS_FROM_REFLECTOR_CACHE=true
IS_USE_REFLECTOR=true
CACHE_QEMU_PKGS_KEY="--cache-qemu-pkgs"
CACHE_QEMU_PKGS_FLAG=false

# Заранее вычисленные степени 1024
export MB=1048576  # 1024^2
export GB=1073741824  # 1024^3
export TB=1099511627776  # 1024^4
export PB=1125899906842624  # 1024^5
export EB=1152921504606846976  # 1024^6

# Строковые константы
export AUTODIR="autocreated_scripts"
export XML_FILE="components.xml"
export XML_PARSER="get_data_from_components_xml.py"
export CHROOT_SCRIPT="run_inside_chroot.sh"
export SHARED_FUNCTIONS="include/shared_functions.sh"
export MAIN_FUNCTIONS="include/main_functions.sh"
export COLORS_CONSTANTS="include/colors.sh"
export TEMPLATES_DIR="templates"
export CREATE_MIRRORLIST_CACHE_SCRIPT="CREATE_MIRRORLIST_CACHE.sh"
export MIRRORLIST_CACHE_FILE="reflector_mirrorlist_cache"
export SYSTEM_MIRRORLIST_FILE="/etc/pacman.d/mirrorlist"
export PKG_LOCAL_CACHE_DIR="cache-repo"

# Получаем путь к каталогу, где находится скрипт
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

# Подключаем файл с цветовыми константами
source $COLORS_CONSTANTS

# Подключаем функции
source $MAIN_FUNCTIONS
source $SHARED_FUNCTIONS

#Функция для принудительной установки кириллического шрифта в tty (если нужно)
force_cyrillic_font() {
    local font_name="cyr-sun16"
    local test_text="test тест"
    if [[ "$TERM" == "linux" ]] && command -v setfont &>/dev/null; then
        echo "$test_text"
        setfont "$font_name"
        echo "$test_text"
        echo -e "${YELLOW}была использована команда setfont $font_name для гарантированного отображения кириллического шрифта${NC}"
    fi
}
# принудительная установка кириллического шрифта в tty (если нужно)
force_cyrillic_font
#будет убрано в англ.версии


# проверяем версию баша
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    echo -e "${GREEN}Версия Bash: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}${NC}"
else
    echo -e "${RED}СБОЙ: Требуется версия Bash 4.3 или выше (используется версия ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]})${NC}" >&2
    exit 1
fi

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "${RED}СБОЙ: Этот скрипт должен быть запущен от имени суперпользователя (root)${NC}" >&2
    exit 1
fi

# используем trap для вызова функции cleanup_all при любом выходе из скрипта
trap 'cleanup_all' EXIT

# фильтрация длинных флагов из аргументов
long_flag_was_used() {
    echo -e "${GREEN}Длинный флаг $1 был использован${NC}"
}
enable_log() {
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        chmod 666 "$LOG_FILE"
    fi
    # добавляем в лог текущую дату и время
    echo "--------------------------------Дата и время: $(date)--------------------------------" >> "$LOG_FILE"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

# фильтрация длинных флагов из аргументов
filtered_args=()
for arg in "$@"; do
    if [[ "$arg" == "$LOG_KEY" ]]; then
        enable_log
        long_flag_was_used "$LOG_KEY"
    elif [[ "$arg" == "$VIEW_ONLY_KEY" ]]; then
        VIEW_ONLY_FLAG=true
        long_flag_was_used "$VIEW_ONLY_KEY"
    elif [[ "$arg" == "$NO_CACHE_MIRRORS" ]]; then
        if [[ -f "$MIRRORLIST_CACHE_FILE" ]]; then
            rm "$MIRRORLIST_CACHE_FILE"
        fi
        long_flag_was_used "$NO_CACHE_MIRRORS"
    elif [[ "$arg" == "$CACHE_QEMU_PKGS_KEY" ]]; then
        CACHE_QEMU_PKGS_FLAG=true
        IS_GET_MIRRORS_FROM_REFLECTOR_CACHE=false
        IS_USE_REFLECTOR=false
        long_flag_was_used "$CACHE_QEMU_PKGS_KEY"
    else
        filtered_args+=("$arg")
    fi
done

# восстанавливаем позиционные параметры (без длинных флагов)
set -- "${filtered_args[@]}"

# проверяем ключи парсинга xml-файла
INSTALL_LOCATION_ID=""
SOFTPACK_ID=""
DRIVERSPACK_ID=""
SETTINGS_ID=""


while getopts "i:s:d:o:" opt; do
  case $opt in
    i)
      # проверка на наличие в xml-файле будет проведена позже
      INSTALL_LOCATION_ID="$OPTARG"
      echo -e "Аргумент после ключа -i: $INSTALL_LOCATION_ID прочитан"
      ;;
    s)
      # проверка на наличие в xml-файле будет проведена позже
      SOFTPACK_ID="$OPTARG"
      echo -e "Аргумент после ключа -s: $SOFTPACK_ID прочитан"
      ;;
    d)
      # проверка на наличие в xml-файле будет проведена позже
      DRIVERSPACK_ID="$OPTARG"
      echo -e "Аргумент после ключа -d: $DRIVERSPACK_ID прочитан"
      ;;
    o)
      # проверка на наличие в xml-файле будет проведена позже
      SETTINGS_ID="$OPTARG"
      echo -e "Аргумент после ключа -o: $SETTINGS_ID прочитан"
      ;;
    \?)
      echo -e "${RED}Неверный параметр -$OPTARG${NC}" >&2
      ;;
  esac
done



# Формат вывода lsblk по умолчанию
export LSBLK_FORMAT="NAME,TYPE,FSTYPE,SIZE,UUID,MOUNTPOINTS,RM,RO,ROTA"
# Читаем ширину терминала
TTY_WIDTH=$(tput cols)

# Создаем массив с возможными вариантами (для возможности изменения)
declare -a LSBLK_FORMATS=(
    "NAME,TYPE,FSTYPE,SIZE,UUID,MOUNTPOINTS,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,UUID,RM,RO,ROTA"
    "NAME,TYPE,FSTYPE,SIZE,UUID,MOUNTPOINTS"
    "NAME,TYPE,FSTYPE,SIZE,UUID"
    "NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS"
    "NAME,TYPE,FSTYPE,SIZE"
    "NAME,TYPE,FSTYPE"
    "NAME,TYPE,FSTYPE,UUID"
)

# создаём ассоциативный массив problems для возможного запланированного выхода 
declare -A problems
#вносим значения в массив (пустая строка - означает, что проблемы нет)

# это чекаем, ещё до этапа открытия крипто-контейнеров:
problems["syntax_problem_in_xml_file"]="" #реализацию можно отложить т.к. пока задаю только корректные данные
# на этапе открытия крипто-контейнеров:
problems["lvm_group_not_found"]="" 
problems["partition_device_by_uuid_not_found"]="" 
problems["lvm_logical_volume_not_found"]="" 
problems["lvm_logical_volume_name_already_exists"]=""
problems["no_free_space_in_vg"]="" 
# на этапе формирования списка запланированных изменений:
problems["btrfs_subvolume_name_already_exists"]=""
problems["no_free_space_for_new_subvolume"]=""


#флаг для запланрованного выхода из скрипта
EXIT_AND_SHOW_PROBLEMS_FLAG=0

#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить имена открытых крипто-контейнеров
declare -A OPENED_CRYPT_CONTAINERS

#создаём массив для хранения uuid зашифрованных разделов
declare -a CRYPT_UUIDS

#создаём массив для хранения имен логических томов (будут преобразованы в uuid)
declare -a CRYPT_LV_VOLUMES

#создаём массив для хранения имен новых точек монтирования
declare -a NEW_MOUNTPOINTS

#создаём массив для хранения имен дополнительных точек монтирования (просто для прописывания в /etc/fstab)
declare -a EXTRA_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить размеры требуемого свободного места
#в группах томов lvm
declare -A ALL_LVM_VOLUMES_REQUIRED_SPACE
ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED=false

show_logo

echo -e "${YELLOW}Перед использованием скрипта также должен быть настроен доступ в интернет и выпонена необходимая минимальная разбивка разделов на диске (подробности в документации).${NC}"
read -p "Enter - продолжить; ctrl+C - прервать"

#Обновление времени
echo -e "${YELLOW}Обновление времени...${NC}"
sync_time

# Настройка зеркал
if [[ "$IS_GET_MIRRORS_FROM_REFLECTOR_CACHE" == true ]]; then
    # если файла с кэшем зеркал не существует, то копируем его из templates
    if [[ ! -f "$MIRRORLIST_CACHE_FILE" ]]; then
        IS_USE_REFLECTOR=true
    else
        #копируем кэш зеркал в системный файл
        cp $MIRRORLIST_CACHE_FILE $SYSTEM_MIRRORLIST_FILE
        echo -e "${YELLOW}Кэш зеркал был использован из файла $MIRRORLIST_CACHE_FILE${NC}"
        IS_USE_REFLECTOR=false
    fi
fi
if [[ "$IS_USE_REFLECTOR" == true ]]; then
    echo -e "${YELLOW}Настройка зеркал...${NC}"
    # если скрипта для рефлектора не существует, то копируем его из templates
    if [[ ! -f "$CREATE_MIRRORLIST_CACHE_SCRIPT" ]]; then
        cp $TEMPLATES_DIR/$CREATE_MIRRORLIST_CACHE_SCRIPT $CREATE_MIRRORLIST_CACHE_SCRIPT
    fi
    #выполняем скрипт для настройки зеркал
    source $CREATE_MIRRORLIST_CACHE_SCRIPT
    #копируем кэш зеркал в системный файл
    cp $MIRRORLIST_CACHE_FILE $SYSTEM_MIRRORLIST_FILE

fi

#1.1.1) запрашиваем формат вывода lsblk с учётом ширины tty
if [[ "$TTY_WIDTH" -lt 150 ]]; then
    request_lsblk_format
else
    echo "Вывод lsblk будет выполнен в формате по умолчанию: $LSBLK_FORMAT. TTY достаточно широкий ($TTY_WIDTH) для вывода всех необходимых данных."
fi

#1.2) получаем от пользователя данные какие компоненты использовать
check_key_and_request_component_id "install_location"
# остальные будут запрашиваться после начала установки системы
# пока что они не требуются

#1.2.1) устанавливаем необходимые пакеты
# откуда устанавливается система

if [[ $(parse_xml install_location get_tweak_iso) == "true" ]]; then
    INSTALL_FROM="iso"
else
    INSTALL_FROM="other_system"
fi


if [[ $INSTALL_FROM == "other_system" ]]; then
    pacman -Syu
fi

packages=("arch-install-scripts" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr" "python" "bc")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование (хотя от этой установки вреда всё равно не будет)

#  для возможного добавления в дальнейшем: xfsprogs, f2fs-tools
# zfs-dkms (или zfs-linux-lts); zfs-utils




#2) получаем данные и xml-файла
#получаем информацию содержащуюся в xml-файле
NEW_MOUNTPOINTS_AMOUNT=$(parse_xml "install_location" "get_amount_of_new_mountpoints")
echo -e "${YELLOW}Количество новых точек монтирования:${NC} $NEW_MOUNTPOINTS_AMOUNT"

EXTRA_MOUNTPOINTS_AMOUNT=$(parse_xml "install_location" "get_amount_of_extra_mountpoints")
echo -e "${YELLOW}Количество дополнительных точек монтирования:${NC} $EXTRA_MOUNTPOINTS_AMOUNT"

for ((i=0; i<$NEW_MOUNTPOINTS_AMOUNT; i++)); do
    NEW_MOUNTPOINT=$(parse_xml "install_location" "get_new_mountpoint" "$i")
    CURRENT_POINT_NAME="new_point$i"
    declare -A "$CURRENT_POINT_NAME"
    #получаем ассоциативный массив из строки
    eval "$CURRENT_POINT_NAME=$NEW_MOUNTPOINT"
    NEW_MOUNTPOINTS+=("$CURRENT_POINT_NAME")
done

for ((i=0; i<$EXTRA_MOUNTPOINTS_AMOUNT; i++)); do
    EXTRA_MOUNTPOINT=$(parse_xml "install_location" "get_extra_mountpoint" "$i")
    CURRENT_POINT_NAME="extra_point$i"
    declare -A "$CURRENT_POINT_NAME"
    eval "$CURRENT_POINT_NAME=$EXTRA_MOUNTPOINT"
    EXTRA_MOUNTPOINTS+=("$CURRENT_POINT_NAME")
done

#3) проходимся по массиву точек монтирования, открываем крипто-контейнеры,
# в которых уже есть существующая структура


# ассоциативный массив, который хранит строки с описанием запланированных изменений
declare -A pending_commands_description


for idx in "${!NEW_MOUNTPOINTS[@]}"; do
    row=${NEW_MOUNTPOINTS[$idx]}
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получает короткие алиасы переменных и xml-файла
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    crypt_mode=${current_row["crypt_mode"]}
    
    if (( idx == 0 )) && [[ "$mount_point" != "/" ]]; then
        echo -e "${RED}Критическая ошибка: первой в $XML_FILE в разделе с точками монтирования должна быть /${NC}" >&2
        exit 1
    fi

    #device выпилен из xml-файла
    #вместо него будет использоваться uuid или lv-volume в зависимости от type
    
    #в каждый кейс прописан подкейс с опциями шифрования
    #устройства с которыми будут проводиться операции будет внесено в поле current_row["device_for_operations"]
    #за исключением случаев, когда крипто-контейнер ещё только нужно будет создать
    #в этих случаях заполнение этого поля будет происходить позже, на внесения измениний
    #данное поле содержать или открытый luks или продублированное имя устройства, если шифрование не используется
    case "$type" in
        "format_ext4")
            #в данном случае задан только партишн, который будет форматироваться

            #получаем uuid
            uuid=${current_row["uuid"]}
            #проверяем существует ли устройство с таким uuid
            if ! device=$(check_uuid_exists "$uuid"); then
                echo -e "${RED}Устройство с uuid '$uuid' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "partition_device_by_uuid_not_found" "Ошибка: устройство с uuid $uuid не найдено"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Устройство с uuid '$uuid' найдено: $device${NC}"
            fi
            current_row["device"]=$device
            ext4_partition=$device
            basename_of_ext4_partition=$(get_device_basename4lsblk "$ext4_partition")
            case "$crypt_mode" in
                "none")
                    current_row["device_for_operations"]=$ext4_partition
                    ;;
                "file"|"pwd")
                    # пояснение: пока не делаем что либо, то тех пор пока
                    #пользователь подтвердит начало установки, до этого измененения на диск мы не вносим
                    pending_commands_description["$basename_of_ext4_partition"]="Будет отформатировано в LUKS, с ext4 внутри для точки монтирования $mount_point"
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none, file, pwd)" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs")

            #получаем uuid
            uuid=${current_row["uuid"]}
            #проверяем существует ли устройство с таким uuid
            if ! device=$(check_uuid_exists "$uuid"); then
                echo -e "${RED}Устройство с uuid '$uuid' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "partition_device_by_uuid_not_found" "Ошибка: устройство с uuid $uuid не найдено"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Устройство с uuid '$uuid' найдено: $device${NC}"
            fi
            current_row["device"]=$device
            #в данном случае заданы подтом, который будет создаваться, и существующий партишн, вне lvm
            subvol_name=${current_row["subvolume"]}
            btrfs_device=$device
            case "$crypt_mode" in
                "none")
                    current_row["device_for_operations"]=$btrfs_device
                    ;;
                "file")
                    #получаем путь к файлу-ключу
                    keyfile=${current_row["keyfile"]}
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_file "$btrfs_device" "$keyfile"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    #имя отркытого контейнера было получено внутри прощедуры open_crypt_container_by_file
                    #и сохранено в ассоциативный массив OPENED_CRYPT_CONTAINERS
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "pwd")
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$btrfs_device"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none, file, pwd)" >&2
                    exit 1
                    ;;
            esac
            ;;
       "new_subvol_in_btrfs_in_lvm")
            subvol_name=${current_row["subvolume"]}
            device=${current_row["lv-volume"]}
            current_row["device"]=$device
            lv_name=$device
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно и тоже
            vg_name=$(get_vg_name_from_fulldevname "$lv_name")

            #сначала нужно отдельно обработать случаи, когда физический том lvm зашифрован
            #в этом случае нужно будет сначала открыть крипто-контейнер
            #иначе проверки на наличие группы томов и логического тома не сработают
            
            #в таких режимах от пользователя также требуется указать партишн с luks в котором лежит pv lvm
            #в случае последующих if'ов в качестве девайса для операций будет использоваться прописанный в xml lv lvm,
            #а не открытый крипто-контейнер, т.к. там pv lvm, а не lv lvm
            #lvm в данном случае сам всё найдёт по имени группы томов, которой принадлежит физический том из крипто-контейнера
            #при этом пользователя надо предупредить о возможной дыре в безопасности, 
            #если в этой группе томов присутствует хотя бы один физический том, который не зашифрован
            
            if [[ "$crypt_mode" == "none_in_file" || "$crypt_mode" == "none_in_pwd" ]]; then
                 #объявляем временный массив для хранения физических томов
                declare -a luks_devices=()
                #заполняем массив pv_devices на основе данных из от uuids из xml-файла
                #заодно проверяем существуют ли устройства с такими uuid
                if ! fill_in_array_by_pv_devices "${current_row["pv-volumes-uuids"]}" luks_devices; then
                    #если была ошибка, то выходим из case для проверки других точек монтирования
                    continue
                fi
                
                #открываем все luks-контейнеры через процедуру
                open_all_luks_devices
                
                unset luks_devices
            
            fi
            

            #проверяем существует ли группа томов
            if ! check_vg_exists "$vg_name"; then
                echo -e "${RED}Группа томов '$vg_name' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "lvm_group_not_found" "Ошибка: группа томов $vg_name не найдена"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Группа томов '$vg_name' найдена${NC}"
            fi

            #проверяем существует ли логический том
            if ! check_lv_exists_by_full_devname "$device"; then
                echo -e "${RED}Логический том '$device' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "lvm_logical_volume_not_found" "Ошибка: логический том $device не найден"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Логический том '$device' найден${NC}"
            fi

                        

            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file")
                    #уже было обработано в if'ах, которые нужно было обязательно сделать
                    #до проверки группы томов и логического тома на их наличие
                    current_row["device_for_operations"]=$lv_name;
                    ;;
                "none_in_pwd")
                    #уже было обработано в if'ах, которые нужно было обязательно сделать
                    #до проверки группы томов и логического тома на их наличие
                    current_row["device_for_operations"]=$lv_name;
                    ;;
                "file_in_none")
                    #получаем путь к файлу-ключу
                    keyfile=${current_row["keyfile"]}
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_file "$btrfs_device" "$keyfile"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "pwd_in_none")
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$btrfs_device"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none_in_none, none_in_file, none_in_pwd, file_in_none, pwd_in_none)" >&2
                    exit 1
                    ;;
            esac
            
            ;;
        "new_ext4_in_lvm")
            device=${current_row["lv-volume"]}
            lv_name=$device
            #получаем имя группы томов
            vg_name=$(get_vg_name_from_fulldevname "$device")
            current_row["device"]=$device
            #аналогично предыдущему случаю
            #нужно сначала открыть luks, если зашифрован именно физический том pv lvm
            #иначе проверки на наличие группы томов и логического тома не сработают
            if [[ "$crypt_mode" == "none_in_file" || "$crypt_mode" == "none_in_pwd" ]]; then                
                #объявляем временный массив для хранения физических томов
                declare -a luks_devices=()
                #заполняем массив pv_devices на основе данных из от uuids из xml-файла
                #заодно проверяем существуют ли устройства с такими uuid
                if ! fill_in_array_by_pv_devices "${current_row["pv-volumes-uuids"]}" luks_devices; then
                    #выходим из case для проверки других точек монтирования
                    continue
                fi
                
                #открываем все luks-контейнеры через процедуру
                open_all_luks_devices

                unset luks_devices
            fi

            


            #проверяем существует ли группа томов
            if ! check_vg_exists "$vg_name"; then
                echo -e "${RED}Группа томов '$vg_name' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "lvm_group_not_found" "Ошибка: группа томов $vg_name не найдена"
                #выходим из case для проверки других точек монтирования
                continue
            fi

            #в данном случае нужно проверить наоборот, что логический том с таким именем не существует
            #в случае btrfs в процессе установке создаётся сабволюм на уже существующем логическом томе
            #а случае ext4 создаётся новый логический том
            if check_lv_exists_by_full_devname "$device"; then
                echo -e "${RED}Логический том '$device' уже существует${NC}" >&2
                add_problem "lvm_logical_volume_name_already_exists" "Ошибка: логический том $device уже существует"
                #выходим из case для проверки других точек монтирования
                continue
            fi

            # проверяем есть ли поле в ассоциативном массиве ALL_LVM_VOLUMES_REQUIRED_SPACE с названием группы томов $vg_name
            if [[ ! -v ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"] ]]; then
                ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"]=0
            fi
            # получаем размер нового тома из переменной size ${current_row["size"]} в байтах (функция задана в начале скрипта)
            size_in_bytes=$(convert_to_bytes "${current_row["size"]}")

            # добавляем размер нового тома в ассоциативный массив
            ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"]=$((ALL_LVM_VOLUMES_REQUIRED_SPACE["$vg_name"] + size_in_bytes))
            ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED=true
            

            size_of_lv=${current_row["size"]}
            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file"|"none_in_pwd")
                    : #эти случаи уже были обработаны в if'ах
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "file_in_none"|"pwd_in_none")
                    #пока что можно просто проверить есть ли свободное место,
                    #это можно спокойно сделать именно на данном этапе
                    #если свободного места нет, то пользователь получит соответствующее сообщение

                    #в этих двух случаях нужно будет создать новые крипто-контейнеры заданного размера
                    # пока что просто отбражаем пользователю планируемые изменения
                    # но не создаём ничего нового
                    pending_commands_description["$lv_name"]="Будет создан логический том $lv_basename в группе томов $vg_name размером $size_of_lv"
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none_in_none, none_in_file, none_in_pwd, file_in_none, pwd_in_none)" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Для $mount_point неизвестный тип: $type (в данном случае предусмотрены: format_ext4, new_subvol_in_btrfs, new_subvol_in_btrfs_in_lvm, new_ext4_in_lvm)" >&2
            exit 1
            ;;
    esac
    
done


for row in "${EXTRA_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получаем короткие алиасы переменных из xml-файла
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    crypt_mode=${current_row["crypt_mode"]}

    case $type in
        "partition"|"subvol_in_btrfs")
            # эти случаи подлежат объединению: нужно просто открыть luks-контейнер
            # если уже существующая файловая система в него завёрнута.
            #получаем uuid
            uuid=${current_row["uuid"]}
            #проверяем существует ли устройство с таким uuid
            if ! device=$(check_uuid_exists "$uuid"); then
                echo -e "${RED}Устройство с uuid '$uuid' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "partition_device_by_uuid_not_found" "Ошибка: устройство с uuid $uuid не найдено"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Устройство с uuid '$uuid' найдено: $device${NC}"
            fi
            current_row["device"]=$device
            case $crypt_mode in
                "none")
                    current_row["device_for_operations"]=$device
                    ;;
                "pwd")
                    open_crypt_container_by_pwd "$device"
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "file")
                    open_crypt_container_by_file "$device"
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none, file, pwd)" >&2
                    exit 1
                    ;;
            esac
            ;;
        "volume_in_lvm"|"subvol_in_btrfs_in_lvm")
            device=${current_row["lv-volume"]}
            current_row["device"]=$device
            lv_name=$device
            vg_name=$(get_vg_name_from_fulldevname "$device")

            if [[ "$crypt_mode" == "none_in_file" || "$crypt_mode" == "none_in_pwd" ]]; then
                #объявляем временный массив для хранения физических томов
                declare -a luks_devices=()
                #заполняем массив pv_devices на основе данных из от uuids из xml-файла
                #заодно проверяем существуют ли устройства с такими uuid
                if ! fill_in_array_by_pv_devices "${current_row["pv-volumes-uuids"]}" luks_devices; then
                    #выходим из case для проверки других точек монтирования
                    continue
                fi
                
                #открываем все luks-контейнеры через процедуру
                open_all_luks_devices

                unset luks_devices
            fi

            #проверяем существует ли группа томов
            if ! check_vg_exists "$vg_name"; then
                echo -e "${RED}Группа томов '$vg_name' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "lvm_group_not_found" "Ошибка: группа томов $vg_name не найдена"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Группа томов '$vg_name' найдена${NC}"
            fi

            #проверяем существует ли логический том
            if ! check_lv_exists_by_full_devname "$device"; then
                echo -e "${RED}Логический том '$device' не существует${NC}" >&2
                # добавляем проблему для запланрованного выхода из скрипта
                add_problem "lvm_logical_volume_not_found" "Ошибка: логический том $device не найден"
                #выходим из case для проверки других точек монтирования
                continue
            else
                echo -e "${GREEN}Логический том '$device' найден${NC}"
            fi

            case $crypt_mode in
                "none_in_none"|"none_in_file"|"none_in_pwd")
                    current_row["device_for_operations"]=$device
                    ;;
                "pwd_in_none")
                    open_crypt_container_by_pwd "$device"
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "file_in_none")
                    open_crypt_container_by_file "$device"
                    current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                *)
                    echo "Для $mount_point неизвестный тип: $crypt_mode (в данном случае предусмотрены: none_in_none, none_in_file, none_in_pwd, pwd_in_none, file_in_none)" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Для $mount_point неизвестный тип: $type (в данном случае предусмотрены: partition, volume_in_lvm, subvol_in_btrfs, subvol_in_btrfs_in_lvm)" >&2
            exit 1
            ;;
    esac

done

check_problems

# начало вывода информации пользователю

echo -e "${CYAN}Информация о вносимых изменениях:${NC}"
echo -e "${GRAY}Построение информации...${NC}"

#создаём временные файлы и сохраняем имя в переменные
LSBLK_RAW_INFO=$(mktemp)
LSBLK_RAW_INFO_UPDATED=$(mktemp)
#записываем содержимое во временный файл
lsblk -o $LSBLK_FORMAT > $LSBLK_RAW_INFO


#записываем первую строку с добавочным текстом (если нужен) во второй временный файл
echo "$(head -n 1 $LSBLK_RAW_INFO)" > $LSBLK_RAW_INFO_UPDATED


#проходися по файлу начиная со второй строки в цикле
while IFS= read -r line; do
    #дублируем строку как есть до изменения
    line_orig="$line"
    #заменяем '│ ' на '│·' чтобы избежать ошибочного разбиения на слова
    #предусмотрены также случаи когда пробелов несколько, а не один
    line=$(echo "$line" | sed -E 's/│ +/│·/g')
    #получаем базовое имя устройства
    #удаляем любые символы отображающие древовидную структуру из начала строки
    device_basename=$(echo "$line" | awk '{print $1}' | sed 's/^[├─└│·]*//')
    type_from_lsblk=$(echo "$line" | awk '{print $2}')
    fstype_from_lsblk=$(echo "$line" | awk '{print $3}')
    #определяем полное имя устройства
    if [[ "$type_from_lsblk" == "lvm" ]]; then
        device_fullname="/dev/mapper/$device_basename"
    elif [[ "$type_from_lsblk" == "part" ]]; then
        device_fullname="/dev/$device_basename"
    elif [[ "$type_from_lsblk" == "crypt" ]]; then
        device_fullname=/dev/mapper/$device_basename
    fi

    if [[ "$fstype_from_lsblk" == "btrfs" ]]; then
        # Используем функцию для окрашивания слова "btrfs"
        line_colored=$(color_text_in_string "$line_orig" "btrfs" "$CYAN")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED


        #используем функцию get_btrfs_subvolumes
        #если вывод пустой, то выводим сообщение об отсутствии сабволюмов и не делаем дальнейших проверок
        add_btrfs_mountpoint_to_array "$device_fullname"
        existing_subvolumes_strings=$(get_btrfs_subvolumes "$device_fullname")
        if [[ -z "$existing_subvolumes_strings" ]]; then
            echo -e "${GRAY}На устройстве $device_fullname нет сабволюмов${NC}" >> $LSBLK_RAW_INFO_UPDATED
 
            #для начала создаём ассоциативный массив (в текущей реализации временный
            #т.к. будет пересоздаваться при каждой итерации цикла)
            declare -A new_btrfs_subvolumes_with_mountpoints
            #заполняем массив
            #нужно передавать имя массива, а не его содержимое
            fill_in_array_by_new_btrfs_subvolumes_for_device "$device_fullname" new_btrfs_subvolumes_with_mountpoints

            #формируем строку с планируемыми изменениями
            new_btrfs_subvolumes_string=$(get_string_for_new_btrfs_subvolumes_for_device new_btrfs_subvolumes_with_mountpoints)
            #если полученная строка не пустая то выводим сообщение о планируемых изменениях
            if [[ -n "$new_btrfs_subvolumes_string" ]]; then 
                echo -e "!${BOLD}Планируемые изменения:${NC} ${GREEN}$new_btrfs_subvolumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
            fi
        else
            #получаем список существующих сабволюмов в формате в одну строку
            existing_subvolumes_string=$(one_line "$existing_subvolumes_strings")
            #получаем массив из строки
            read -r -a existing_subvolumes <<< "$existing_subvolumes_string"
            #выводим список сабволюмов на экран
            echo -e "!${BOLD}Имеющиеся сабволюмы:${NC} ${CYAN}$existing_subvolumes_string${NC}" >> $LSBLK_RAW_INFO_UPDATED
            
            #для начала создаём ассоциативный массив (в текущей реализации временный
            #т.к. будет пересоздаваться при каждой итерации цикла)
            declare -A new_btrfs_subvolumes_with_mountpoints
            #заполняем массив
            #нужно передавать имя массива, а не его содержимое
            fill_in_array_by_new_btrfs_subvolumes_for_device "$device_fullname" new_btrfs_subvolumes_with_mountpoints

            #формируем строку с планируемыми изменениями
            new_btrfs_subvolumes_string=$(get_string_for_new_btrfs_subvolumes_for_device new_btrfs_subvolumes_with_mountpoints)
            #если ассоциативный массив не пустой, то проверяем, есть ли в ней уже существующие сабволюмы
            if [[ -n "$new_btrfs_subvolumes_string" ]]; then 
                is_unique_flag=0
                for subvolume_with_mount_point in "${!new_btrfs_subvolumes_with_mountpoints[@]}"; do
                    #проверяем, есть ли такой сабволюм в массиве existing_subvolumes
                    for existing_subvolume in "${existing_subvolumes[@]}"; do
                        if [[ "$subvolume_with_mount_point" == "$existing_subvolume" ]]; then
                            echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Сабволюм $existing_subvolume уже существует${NC}" >> $LSBLK_RAW_INFO_UPDATED
                            is_unique_flag=1
                            #окрашиваем в красный
                            new_btrfs_subvolumes_string=$(color_text_in_string "$new_btrfs_subvolumes_string" "$existing_subvolume" "$RED")
                        fi
                    done
                done
                #если the_same_flag равен 1, то выводим сообщение об ошибке
                if (( is_unique_flag == 0 )); then
                    #окрашиваем в зеленый
                    new_btrfs_subvolumes_string="${GREEN}${new_btrfs_subvolumes_string}${NC}"
                else
                    #выводим в этой секции на случай, если совпадений было несколько
                    echo -e "!${RED}отредактируйте ${GREEN}${XML_FILE}${NC}${RED} или измените разметку${NC}" >> $LSBLK_RAW_INFO_UPDATED
                    add_problem "btrfs_subvolume_name_already_exists" "Ошибка: в файле конфигурации нужно прописать уникальные имена для новых сабволюмов"
                fi
                    echo -e "!${BOLD}Планируемые изменения:${NC} $new_btrfs_subvolumes_string" >> $LSBLK_RAW_INFO_UPDATED

            fi
        fi
        #удаляем временный ассоциативный массив, если он существует
        if declare -p new_btrfs_subvolumes_with_mountpoints &>/dev/null; then
            unset new_btrfs_subvolumes_with_mountpoints
        fi
    elif [[ "$fstype_from_lsblk" == "LVM2_member" ]]; then
        #окрашиваем найденный элемент
        line_colored=$(color_text_in_string "$line_orig" "LVM2_member" "$YELLOW")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
        if [[ "$type_from_lsblk" == "crypt" ]]; then
            device_fullname="/dev/mapper/$device_basename"
        else
            device_fullname="/dev/$device_basename"
        fi
        #получаем имя группы томов
        vg_name=$(get_vg_name_for_pv "$device_fullname")
        #если том не принадлежит ни одной группе томов, нет смысла делать дальнейшие проверки
        if [[ -z "$vg_name" ]]; then
            echo -e "!${GRAY}Не принадлежит ни одной группе томов${NC}" >> $LSBLK_RAW_INFO_UPDATED
        else
            #выводим имя группы томов
            echo -e "!${BOLD}Имя группы томов:${NC} ${YELLOW}$vg_name${NC}" >> $LSBLK_RAW_INFO_UPDATED

            #создаём временный ассоциативный массив для хранения новых томов lvm
            declare -A new_lvm_volumes
            declare -A new_lvm_volumes_is_luks
            #заполняем массив
            fill_in_array_by_new_lvm_volumes_for_group "$vg_name" new_lvm_volumes new_lvm_volumes_is_luks
            #формируем строку с планируемыми изменениями
            new_lvm_volumes_string=$(get_string_for_new_lvm_volumes_for_group new_lvm_volumes new_lvm_volumes_is_luks)
           
            #поучаем список существующий логических томов с преобразованием в одну строку
            existing_lvm_volumes_string=$(one_line "$(safe_lvs --noheading -o lv_name "$vg_name" | tr -d ' ')")
            #получаем массив из строки
            read -r -a existing_lvm_volumes <<< "$existing_lvm_volumes_string"
            #проходимся по массивам для поиска совпадений
            if [[ -n "$new_lvm_volumes_string" ]]; then 
                is_unique_flag=0

                for new_lvm_volume in "${!new_lvm_volumes[@]}"; do
                    for existing_lvm_volume in "${existing_lvm_volumes[@]}"; do
                        if [[ "$new_lvm_volume" == "$existing_lvm_volume" ]]; then
                            echo -e "!${RED}${BOLD}Ошибка:${NC} ${RED}Том $existing_lvm_volume уже существует${NC}" >> $LSBLK_RAW_INFO_UPDATED
                            is_unique_flag=1
                            #окрашиваем в красный
                            new_lvm_volumes_string=$(color_text_in_string "$new_lvm_volumes_string" "$existing_lvm_volume" "$RED")
                        fi
                    done
                done
                if (( is_unique_flag == 0 )); then
                    new_lvm_volumes_string="${GREEN}${new_lvm_volumes_string}${NC}"
                else
                    #выводим в этой секции на случай, если совпадений было несколько
                    echo -e "!${RED}отредактируйте ${GREEN}${XML_FILE}${NC}${RED} или измените разметку${NC}" >> $LSBLK_RAW_INFO_UPDATED
                    add_problem "lvm_logical_volume_name_already_exists" "Ошибка: в файле конфигурации нужно прописать уникальные имена для новых томов lvm"
                fi

                echo -e "!${BOLD}Планируемые изменения:${NC} $new_lvm_volumes_string" >> $LSBLK_RAW_INFO_UPDATED
            fi
        fi
        #удаляем временные ассоциативные массивы, если они существуют
        if declare -p new_lvm_volumes &>/dev/null; then
            unset new_lvm_volumes
        fi
        if declare -p new_lvm_volumes_is_luks &>/dev/null; then
            unset new_lvm_volumes_is_luks
        fi

    elif [[ "$fstype_from_lsblk" == "ext4" ]]; then
        #окрашиваем найденный элемент
        line_colored=$(color_text_in_string "$line_orig" "ext4" "$BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    elif [[ "$fstype_from_lsblk" == "crypto_LUKS" ]]; then
        #окрашиваем найденный элемент
        line_colored=$(color_text_in_string "$line_orig" "crypto_LUKS" "$LIGHT_BLUE")
        echo -e "$line_colored" >> $LSBLK_RAW_INFO_UPDATED
    else
        #пишем строку как есть
        echo "$line_orig" >> $LSBLK_RAW_INFO_UPDATED
    fi
    #т.к. в ext4 можно форматнуть любой раздел, эту проверку осуществляем вне предыдущего if
    
    #проверяем отмечен ли для форматирования через функцию check_ext4_partitions_to_format_with_their_mount_points
    string_checker=$(check_ext4_partitions_to_format_with_their_mount_points "$device_fullname")
    if [[ -n "$string_checker" ]]; then
        echo -e "!${BOLD}Планируемые изменения:${NC} ${RED}$string_checker${NC}" >> $LSBLK_RAW_INFO_UPDATED
        echo -e "!${RED}Перед тем как продолжить, проверьте что на устройстве нет важных данных${NC}" >> $LSBLK_RAW_INFO_UPDATED
        echo -e "!${YELLOW}Если хотите прервать выполнение скрипта для перепроверки, нажмите ctrl+c${NC}" >> $LSBLK_RAW_INFO_UPDATED
    fi
done < <(sed '1d' $LSBLK_RAW_INFO)

#обновляем первый временный файл и обнуляем второй
mv $LSBLK_RAW_INFO_UPDATED $LSBLK_RAW_INFO
#выводим содержимое временного файла
less -R -F -X -P ' ↑↓ прокрутка | q — выход' "$LSBLK_RAW_INFO"


make_pause

check_problems
 
 #проверяем доступное свободное место в группах томов
if [[ "$ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED" == "true" ]]; then
    for vg_name in "${!ALL_LVM_VOLUMES_REQUIRED_SPACE[@]}"; do
        required_space=${ALL_LVM_VOLUMES_REQUIRED_SPACE[$vg_name]}
        echo "Требуемый размер для группы томов $vg_name: $required_space байт ($(echo "$required_space / $GB" | bc) гигов)"
        #проверяем доступное свободное место группе томов в байтах
        free_space=$(check_free_space_in_vg_in_bytes "$vg_name")
        echo "Доступное свободное место в группе томов $vg_name: $free_space байт ($(echo "$free_space / $GB" | bc) гигов)"
        if [[ "$free_space" -lt "$required_space" ]]; then
            echo "Ошибка: Доступное свободное место в группе томов $vg_name меньше требуемого" >&2
            echo "Увеличте свободное место. После чего перезапустите установку" >&2
            #добавляем проблему для запланрованного выхода из скрипта
            add_problem "lvm_group_not_enough_free_space" "Ошибка: свободного места в группе томов $vg_name меньше требуемого (требуется $(convert_bytes_to_gb "$required_space") свободного места, а доступно $(convert_bytes_to_gb "$free_space"))"
        else
            echo "свободного места в группе томов $vg_name достаточно"
        fi
    done
fi

check_problems

if [[ "$VIEW_ONLY_FLAG" == "true" ]]; then
    echo -e "${GREEN}Этап просмотра и сверки планируемых изменений завершён${NC}"
    exit 0
fi


make_pause

echo -e "${GREEN}Этап просмотра и сверки планируемых изменений завершён${NC}"
echo -e "${YELLOW}Если всё в порядке, введите слово ${BOLD}${GREEN}INSTALL${NC}${YELLOW} капсом для начала установки системы${NC}"

read -p "Введите слово INSTALL капсом для продолжения: " user_input
if [[ "$user_input" != "INSTALL" ]]; then
    echo -e "${RED}Ошибка: вы должны ввести слово ${BOLD}${GREEN}INSTALL${NC}${RED} капсом. Установка отменена.${NC}"
    exit 1
fi

#5) ЗАПУСК УСТАНОВКИ

echo -e "${GREEN}Начинаем установку системы...${NC}"

# получаем от пользователя остальные параметры, если они не были переданы в скрипт через ключи
check_key_and_request_component_id "softpack"
check_key_and_request_component_id "driverspack"
check_key_and_request_component_id "settings"



#создаём временный каталог для монтирования системы
INST_DIR=$(mktemp -d)



# случаи для legacy будут добавлены потом
EFI_UUID="$(parse_xml install_location get_efi_uuid)"
# Получаем имя устройства через UUID с проверкой существования
if [[ -n "$EFI_UUID" ]] && [[ -e "/dev/disk/by-uuid/$EFI_UUID" ]]; then
    EFI_DEV=$(readlink -f "/dev/disk/by-uuid/$EFI_UUID")
else
    echo -e "${RED}Ошибка: EFI устройство с UUID $EFI_UUID не найдено${NC}" >&2
    exit 1
fi
EFI_NEW_LOCATION="$(parse_xml install_location get_efi_new_location)"
EFI_SYS_NAME="$(parse_xml install_location get_efi_bootlabel)"

#получаем список пакетов для pacstrap
SOFT_PACK1="$(parse_xml softpack get_pkgs_pacstrap)"

# Показываем пользователю список записей EFI
echo -e "${YELLOW}Список записей EFI:${NC}"
efibootmgr

# Проверяем уникальность имени и предлагаем варианты
while true; do
    if efibootmgr | grep -q "$EFI_SYS_NAME"; then
        echo -e "${RED}Загрузчик с именем ${MAGENTA}$EFI_SYS_NAME${RED} уже существует.${NC}"
        read -p "Хотите перезаписать существующий загрузчик? (type YES using Capital letters): " overwrite
        if [[ $overwrite =~ ^YES$ ]]; then
            echo -e "${GREEN}Будет выполнена перезапись существующего загрузчика.${NC}"
            break
        else
            read -p "Введите другое имя загрузчика в EFI-разделе: " EFI_SYS_NAME
        fi
    else
        echo -e "${GREEN}Имя загрузчика ${MAGENTA}$EFI_SYS_NAME${GREEN} уникально и будет использовано.${NC}"
        break
    fi
done

#проходимся по массиву новых точек монтирования ещё раз, для монитрования в рабочий каталого перед установкой
for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получаем короткие алиасы переменных из xml-файла
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    crypt_mode=${current_row["crypt_mode"]}

    case $type in
        "format_ext4")
            :
            case $crypt_mode in
                "none")
                    :
                    # поле device_for_operation уже получено в предыдущем цикле
                    ;;
                "pwd")
                    create_and_open_crypt_container_with_new_pwd ${current_row["device"]}
                    #получаем имя раздела для монтирования
                    current_row["device_for_operations"]="${current_row["opened_crypt_container_fullname"]}"
                    ;;
                "file")
                    create_and_open_crypt_container_with_file ${current_row["device"]} ${current_row["keyfile"]}
                    #получаем имя раздела для монтирования
                    current_row["device_for_operations"]="${current_row["opened_crypt_container_fullname"]}"
                    ;;
            esac
            #форматируем раздел
            if mkfs.ext4 ${current_row["device_for_operations"]}; then
                echo -e "${GREEN}Раздел успешно отформатирован.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось отформатировать раздел.${NC}" >&2
                exit 1
            fi
            
            #создаём каталог $INST_DIR$mount_point если он не существует
            if mkdir -p $INST_DIR$mount_point; then
                echo -e "${GREEN}Каталог $INST_DIR$mount_point успешно создан или уже существует.${NC}"
            else
                echo -e "${RED}Ошибка: при создании каталога $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            
            #монтируем раздел
            if mount ${current_row["device_for_operations"]} $INST_DIR$mount_point; then
                echo -e "${GREEN}Раздел успешно смонтирован в $INST_DIR$mount_point.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось смонтировать раздел в $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            ;;
        "new_subvol_in_btrfs" | "new_subvol_in_btrfs_in_lvm")
            #в этих случаях поле device_for_operation уже получено
            #в предыдущем цикле для всех опций шифрования
            btrfs_device=${current_row["device_for_operations"]}
            subvol_name=${current_row["subvolume"]}
            echo "btrfs_device: $btrfs_device"
            echo "subvol_name: $subvol_name"
            # получаем временную точку монтирования для btrfs-устройства
            # add_btrfs_mountpoint_to_array "$btrfs_device"
            btrfs_mountpoint=$(get_btrfs_mountpoint "$btrfs_device")
            echo "btrfs_mountpoint: $btrfs_mountpoint"
            echo "ALL_BTRFS_MOUNTPOINTS: ${ALL_BTRFS_MOUNTPOINTS[@]}"
            
            #создаём подтом
            if btrfs subvolume create "${btrfs_mountpoint}/$subvol_name"; then
                echo -e "${GREEN}Подтом успешно создан.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось создать подтом.${NC}" >&2
                exit 1
            fi
            
            #создаём каталог $INST_DIR$mount_point если он не существует
            if mkdir -p $INST_DIR$mount_point; then
                echo -e "${GREEN}Каталог $INST_DIR$mount_point успешно создан или уже существует.${NC}"
            else
                echo -e "${RED}Ошибка: при создании каталога $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            
            #монтируем подтом в каталог установки (внутри chroot'а)
            if mount -o subvol=$subvol_name $btrfs_device $INST_DIR$mount_point; then
                echo -e "${GREEN}Подтом успешно смонтирован в $INST_DIR$mount_point.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось смонтировать подтом в $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            ;;
        "new_ext4_in_lvm")
            size_of_lv=${current_row["size"]}
            lv_name=${current_row["lv-volume"]}
            device=$lv_name
            vg_name=$(get_vg_name_from_fulldevname "$device")
            #получаем имя логического тома
            #именно таким способом т.к. не известно было ли прописано
            #через mapper или нет, поэтому обычный basename тут не подходит
            lv_basename=$(get_lv_name_from_fulldevname "$device")
            #создаём том lvm
            if lvcreate -L $size_of_lv -n $lv_basename $vg_name; then
                echo -e "${GREEN}Том LVM успешно создан: $lv_basename.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось создать том LVM.${NC}" >&2
                exit 1
            fi
            
            #создаём каталог $INST_DIR$mount_point если он не существует
            if mkdir -p $INST_DIR$mount_point; then
                echo -e "${GREEN}Каталог $INST_DIR$mount_point успешно создан или уже существует.${NC}"
            else
                echo -e "${RED}Ошибка: при создании каталога $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            case $crypt_mode in
                "none_in_none" | "none_in_pwd" | "none_in_file")
                    #в этих случаях поле device_for_operation уже получено
                    :
                    ;;
                "pwd_in_none")
                    #используем функцию для создания и открытия крипто-контейнера
                    create_and_open_crypt_container_with_new_pwd "$lv_name"
                    current_row["device_for_operations"]="${current_row["opened_crypt_container_fullname"]}"
                    ;;
                "file_in_none")
                    #используем функцию для создания и открытия крипто-контейнера
                    create_and_open_crypt_container_with_file "$lv_name" "${current_row["keyfile"]}"
                    current_row["device_for_operations"]="${current_row["opened_crypt_container_fullname"]}"
                    ;; 
            esac
            # создаём файловую систему ext4 на открытом контейнере
            if mkfs.ext4 "${current_row["device_for_operations"]}"; then
                 echo -e "${GREEN}Файловая система ext4 успешно создана на открытом контейнере.${NC}"
            else
                 echo -e "${RED}Ошибка: не удалось создать файловую систему ext4 на открытом контейнере.${NC}" >&2
                 exit 1
            fi
            
            # монтируем том lvm или содержимое контейнера luks в каталог установки (внутри chroot'а)
            if mount "${current_row["device_for_operations"]}" "$INST_DIR$mount_point"; then
                echo -e "${GREEN}Том LVM или содержимое контейнера LUKS успешно смонтировано в $INST_DIR$mount_point.${NC}"
            else
                echo -e "${RED}Ошибка: не удалось смонтировать том LVM или содержимое контейнера LUKS в $INST_DIR$mount_point.${NC}" >&2
                exit 1
            fi
            ;;
    esac

done

#монтируем дополнительные разделы
for row in "${EXTRA_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получаем короткие алиасы переменных из xml-файла
    mount_point=${current_row["mount_point"]}
    device_for_operations=${current_row["device_for_operations"]}
    #тут уже не нужно проходиться по значениям type и crypt_mode

    if mkdir -p $INST_DIR$mount_point; then
        echo -e "${GREEN}Каталог $INST_DIR$mount_point успешно создан или уже существует.${NC}"
    else
        echo -e "${RED}Ошибка: при создании каталога $INST_DIR$mount_point.${NC}" >&2
        exit 1
    fi

    fs_type=$(lsblk -o FSTYPE -n $device_for_operations)
    mount_options=""
    if [[ "$fs_type" == "btrfs" ]]; then
        # Для btrfs используем subvol только если он определен
        subvol_name=${current_row["subvolume"]}
        if [[ -n "$subvol_name" ]]; then
            mount_options="-t btrfs -o subvol=$subvol_name"
        else
            echo -e "${RED}Не указан subvolume для монтирования раздела $mount_point${NC}" >&2
            exit 1
        fi
    elif [[ "$fs_type" == "ntfs" ]]; then
        mount_options="-t ntfs3 -o uid=$(parse_xml settings get_uid),gid=$(parse_xml settings get_gid),locale=$(parse_xml settings get_ntfs_locale),$(parse_xml settings get_ntfs_mask)"
    elif [[ "$fs_type" == "ext4" ]]; then
        mount_options="-t ext4"
    elif [[ "$fs_type" == "f2fs" ]]; then
        mount_options="-t f2fs"
    elif [[ "$fs_type" == "xfs" ]]; then
        mount_options="-t xfs"
    elif [[ "$fs_type" == "crypto_LUKS" ]]; then
        echo -e "${RED}Возможно, неправильно указаны параметр crypt_mode для раздела точки монтирования $mount_point${NC}" >&2
        exit 1
    elif [[ "$fs_type" == "zfs" ]]; then
        echo -e "${RED} Поддержка ZFS в этом скрипте пока не реализована${NC}" >&2
        exit 1
    else
        echo -e "${RED} Неизвестный тип файловой системы: $fs_type${NC}" >/dev/tty
        echo -e "${RED}1. Смонтировать её без указания опций?${NC}" >/dev/tty
        echo -e "${RED}2. Указать опции вручную?${NC}" >/dev/tty
        echo -e "${RED}3. Использовать опции для $fs_type по умолчанию?${NC}" >/dev/tty
        echo -e "${RED}4. Выйти из скрипта${NC}" >/dev/tty
        read -p "Введите номер действия: " user_input
        if [[ "$user_input" == "1" ]]; then
            mount_options=""
        elif [[ "$user_input" == "2" ]]; then
            read -p "Введите опции: " mount_options
        elif [[ "$user_input" == "3" ]]; then
            mount_options="-t $fs_type"
        elif [[ "$user_input" == "4" ]]; then
            exit 1
        else
            echo -e "${RED}Неизвестное действие: $user_input${NC}" >&2
            exit 1
        fi
    fi

    if mount $mount_options $device_for_operations $INST_DIR$mount_point; then
        echo -e "${GREEN}Раздел успешно смонтирован в $INST_DIR$mount_point.${NC}"
    else
        echo -e "${RED}Ошибка: не удалось смонтировать раздел в $INST_DIR$mount_point.${NC}" >&2
        echo -e "${RED}Убедитесь, что раздел $device_for_operations существует и доступен.${NC}" >&2
        echo -e "${RED}Убедитесь, что файловая система $(lsblk -o FSTYPE -n $device_for_operations) поддерживается системой.${NC}" >&2
        exit 1
    fi
done


#монтируем EFI-раздел
if mkdir -p $INST_DIR/$EFI_NEW_LOCATION; then
    echo -e "${GREEN}Каталог $INST_DIR/$EFI_NEW_LOCATION успешно создан или уже существует.${NC}"
else
    echo -e "${RED}Ошибка: при создании каталога $INST_DIR/$EFI_NEW_LOCATION.${NC}" >&2
    exit 1
fi
if mount $EFI_DEV $INST_DIR/$EFI_NEW_LOCATION; then
    echo -e "${GREEN}EFI-раздел успешно смонтирован в $INST_DIR/$EFI_NEW_LOCATION.${NC}"
else
    echo -e "${RED}Ошибка: не удалось смонтировать EFI-раздел в $INST_DIR/$EFI_NEW_LOCATION.${NC}" >&2
    exit 1
fi


# кеширование пакетов в qemu
if [[ "$CACHE_PKGS_FLAG" == true ]]; then
    # гарантируем, что целевая директория существует внутри нового root
    mkdir -p "$INST_DIR/var/cache/pacman/pkg"
    mount --bind  "$(pwd)/$PKG_LOCAL_CACHE_DIR" "$INST_DIR/var/cache/pacman/pkg"
fi
if [[ "$CACHE_QEMU_PKGS_FLAG" == true ]]; then
    add_local_cache_servers_to_file /etc/pacman.conf
    pacman -Sy
fi

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1


# Генерация fstab
genfstab -U $INST_DIR > $INST_DIR/etc/fstab
NOFAIL_TEMPLATE_LIST=$(parse_xml softpack get_nofail_templates)
for NOFAIL_TEMPLATE in ${NOFAIL_TEMPLATE_LIST[@]}; do
    sed -i -r '/\s+'$NOFAIL_TEMPLATE'/ { /nofail/! s/(defaults)(.*)/\1,nofail\2/ }' $INST_DIR/etc/fstab
done


# настройка зашифрованных разделов
for row in "${NEW_MOUNTPOINTS[@]}" "${EXTRA_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"
    crypt_mode=${current_row["crypt_mode"]}
    if [[ $crypt_mode == *"pwd"* || $crypt_mode == *"file"* ]]; then
        configure_crypt_volumes_by_ref "$row"
    fi
done


#копирование дополнительных файлов, для выполнения внутри системы (должны быть в одном каталоге с этим)
cp $SCRIPT_DIR/$CHROOT_SCRIPT $INST_DIR
cp $SCRIPT_DIR/$XML_PARSER $INST_DIR
cp $SCRIPT_DIR/$XML_FILE $INST_DIR
cp $SCRIPT_DIR/$SHARED_FUNCTIONS $INST_DIR

if  [[ "$CACHE_QEMU_PKGS_FLAG" == true ]]; then
    add_local_cache_servers_to_file $INST_DIR/etc/pacman.conf
fi

#получаем список архивов для распаковки в домашнюю папку пользователя
ARCHIVES_4HOME="$(parse_xml softpack get_archs4home)"

#копирование и распоковка архивов с файлами для домашнего каталога (будут распаковываны в chroot'е)
for archive in $ARCHIVES_4HOME; do
    cp $SCRIPT_DIR/$archive $INST_DIR
done

# копируем настроенные зеркала:
if [[ "$IS_GET_MIRRORS_FROM_REFLECTOR_CACHE" == true ]]; then
    cp $MIRRORLIST_CACHE_FILE $INST_DIR$SYSTEM_MIRRORLIST_FILE
else
    cp $SYSTEM_MIRRORLIST_FILE $INST_DIR$SYSTEM_MIRRORLIST_FILE
fi



#-------------------------------
# Chroot в новую систему
# передаём в скрипт idшники установки
arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SOFTPACK_ID\" \"$DRIVERSPACK_ID\" \"$INSTALL_LOCATION_ID\" \"$SETTINGS_ID\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/$CHROOT_SCRIPT
rm $INST_DIR/$XML_PARSER
rm $INST_DIR/$XML_FILE
rm $INST_DIR/$(basename $SHARED_FUNCTIONS)

if [[ "$CACHE_QEMU_PKGS_FLAG" == true ]]; then
    remove_local_cache_servers_from_file $INST_DIR/etc/pacman.conf
fi


#размонтируем раздел EFI
if umount $INST_DIR/$EFI_NEW_LOCATION; then
    echo -e "${GREEN}EFI-раздел успешно размонтирован.${NC}"
else
    echo -e "${RED}Ошибка: не удалось размонтировать EFI-раздел.${NC}" >&2
    exit 1
fi

# Размонтирование всех разделов
if umount -R $INST_DIR; then
    echo -e "${GREEN}Все разделы успешно размонтированы.${NC}"
else
    echo -e "${RED}Ошибка: не удалось размонтировать все разделы.${NC}" >&2
    exit 1
fi
if [ -z "$(ls -A $INST_DIR)" ]; then
    rmdir $INST_DIR
else
    echo -e "${RED}Каталог $INST_DIR не пустой. Удаление не выполнено.${NC}"
fi

echo -e "${GREEN}ALL DONE${NC}"


if [[ $INSTALL_FROM == "other_system" ]]; then
    echo -e "${YELLOW}не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)${NC}"
    read -p "Нажмите Enter для выхода..."
else
    echo -e "${YELLOW}Установка завершена. Перезагрузите компьютер.${NC}"
fi
