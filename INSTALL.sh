#!/usr/bin/env bash
# https://github.com/Antony-hash512/Pure-Arch-Linux_-installer-v2/
read -r -d '' LOGO <<'EOF'
 ____                 
|  _ \ _   _ _ __ ___ 
| |_) | | | | '__/ _ \
|  __/| |_| | | |  __/
|_|    \__,_|_|  \___|
                      
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
#1) задаём различные переменные и константы
#1.1) проверяем кириллический шрифт (будет убрано в англ.версии)
#1.2) устанавливаем необходимые пакеты
#2) получаем от пользователя данные какие компоненты использовать
#2.1) получаем данные из xml-файла
#2.2) проверяем корректность данных в xml-файле (задача на потом, пока что работаем с заведомо корректними данными)
#3) проходимся по массиву точек монтирования, открываем крипто-контейнеры, в которых уже есть существующая
#структура на этом же этапе обрабатываем некоторые виды ошибок
#4) взяв за основу вывод команду lsblk отображаем пользователя информацию о:
#  * уже существующих поддомах на btrfs
#  * поддома btrfs, которые планируются к созданию (и какая точка мониторования планируется к привязке)
#  * логические тома lvm, которые планируются к созданию (+ точки монирования)
#  * крипто-контейны, luks, которые планируются к созданию и что в них планируется разместить
#  * существующий проблемах, например нехватки свободного место и т.д.
#5) выполняем установку системы после явного подтверждения пользователем

: <<'TODO'


* добавить логику добавления в CRYPT_VOLUMES для общего случая
(или понять какая в новом скрипте ему альтернатива)
* протестировать установку на vm
* добавить ключ для только просмотра изменений без установки
* проверить открытия luksов по кейфайлу (в случаях с ext4 может быть создан новый кейфайл, в случаях с btrfs нет)
* добавить полноценную поддержку extra точек монтирования (туда ничего не уставнавливается,
они просто прописываются в /etc/fstab) + тесты для них
* зарелизить бету !!!! <-- ВАЖНО НАКОНЕЦ-ТО НАДО ЗАРЕЛИЗИТЬ ГОТОВЫЙ MVP
* ввести ключ для автоматической установки формата вывода lsblk
* написать функцию, для проверки гарантированного свободного места в btrfs томах
* создать функцию, которая будет проверять корректность данных в xml-файле
* протестировать написанные функции (опционально)

* реализовать поддержку старых ноутбуков с legacy bios
* написать документацию

* добавить проверку хука при установке шифрования до установки системы
* допилить реализацию softpack_tweaks
* добавить копирование и распакову архивов для root
* уточнить, инфу про необязательносить выноса /boot в отдельный раздел и возможность его шифрования
* релизовать и протестировать поддержку других систем инициализации на случай установки Artix
* если не передумаю, сделать возможным установку не из Arch-подобных систем с использованием chroot вместо arch-chroot
* если не передумаю вернуть создание скриптов для автоматического удаления из прошлой версии
    * разобраться что не так с удалением сабволюмов через автоматический скрипт

TODO

# Подключаем файл с цветовыми переменными
source include/colors.sh

# Обработка аргументов командной строки
# логирование (если задан ключ --log)
enable_log=false

# фильтрация --log из аргументов
filtered_args=()
for arg in "$@"; do
    if [[ "$arg" == "--log" ]]; then
        enable_log=true
    else
        filtered_args+=("$arg")
    fi
done

# восстанавливаем позиционные параметры (без --log и т.д.)
set -- "${filtered_args[@]}"

if $enable_log; then
    #если файл log.txt не существует, то создаём его с правами 666
    if [[ ! -f log.txt ]]; then
        touch log.txt
        chmod 666 log.txt
    fi
    #добавляем в лог текущую дату и время
    echo "--------------------------------Дата и время: $(date)--------------------------------" >> log.txt
    exec > >(tee -a log.txt) 2>&1
fi

# пренудительная установка кириллического шрифта
if [[ "$TERM" == "linux" ]] && command -v setfont &>/dev/null; then
    echo "test тест"
    setfont cyr-sun16
    echo "test тест"
    echo -e "${YELLOW}была использована команда setfont cyr-sun16 для гарантированного отображения кириллического шрифта${NC}"
fi

# проверяем ключи парсинга xml-файла
INSTALL_LOCATION_ID=""
SOFTPACK_ID=""
DRIVERS_ID=""
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
      SOFT_PACK_ID="$OPTARG"
      echo -e "Аргумент после ключа -s: $SOFT_PACK_ID прочитан"
      ;;
    d)
      # проверка на наличие в xml-файле будет проведена позже
      DRIVERS_ID="$OPTARG"
      echo -e "Аргумент после ключа -d: $DRIVERS_ID прочитан"
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

# проверяем версию баша
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    echo -e "${GREEN}Версия Bash: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}${NC}"
else
    echo -e "${RED}Требуется версия Bash 4.3 или выше (используется версия ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]})${NC}" >&2
    exit 1
fi

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mОШИБКА: Этот скрипт должен быть запущен от имени суперпользователя (root)\033[0m" >&2
    exit 1
fi


#1) задаём различные переменные и константы
# Подключаем функции
source include/main_functions.sh
source include/shared_functions.sh
# используем trap для вызова функции cleanup_all при любом выходе из скрипта
trap 'cleanup_all' EXIT


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

# Получаем путь к каталогу, где находится скрипт
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

# Формат вывода lsblk по умолчанию
export LSBLK_FORMAT="NAME,TYPE,FSTYPE,SIZE,UUID,RM,RO,ROTA"
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
exit_and_show_problems_flag=0



#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить имена открытых крипто-контейнеров
declare -A OPENED_CRYPT_CONTAINERS

#создаём массив для хранения имен новых точек монтирования
declare -a NEW_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить размеры требуемого свободного места
#в группах томов lvm
declare -A ALL_LVM_VOLUMES_REQUIRED_SPACE
ALL_LVM_VOLUMES_REQUIRED_SPACE_IS_USED=false

show_logo

echo -e "${YELLOW}Перед использованием скрипта также должен быть настроен доступ в интернет и выпонена необходимая минимальная разбивка разделов на диске (подробности в документации).${NC}"
read -p "Enter - продолжить; ctrl+C - прервать"

#Обновление времени
timedatectl set-ntp true

#1.1.1) запрашиваем формат вывода lsblk с учётом ширины tty
if [[ "$TTY_WIDTH" -lt 150 ]]; then
    request_lsblk_format
else
    echo "Вывод lsblk будет выполнен в формате по умолчанию: $LSBLK_FORMAT. TTY достаточно широкий ($TTY_WIDTH) для вывода всех необходимых данных."
fi


#1.2) устанавливаем необходимые пакеты
pacman -Sy
packages=("arch-install-scripts" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr" "python" "bc")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)


#2) получаем от пользователя данные какие компоненты использовать


# Если INSTALL_LOCATION_ID не был задан через ключ -i или указанное значение не найдено
if [[ -z "$INSTALL_LOCATION_ID" ]]; then
    # Выбор места установки
    INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID мест установки")
else
    # если уже задан значит было получено из ключа -i
    # проверяем существует ли указанное место установки
    if ! check_install_location_exists "$INSTALL_LOCATION_ID"; then
        echo -e "${RED}Указанное через ключ -i место установки '$INSTALL_LOCATION_ID' не найдено в файле ${GREEN}$XML_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}Используем указанное место установки из ключа -i: $INSTALL_LOCATION_ID${NC}"
fi
# Имена других компонентов будут точно так же получены из ключей или запрошены у пользовтеля
# когда начнётся работа над частью скрипта, которая отвечает за установку

#2.1) получаем данные и xml-файла
#получаем информацию содержащуюся в xml-файле
NEW_MOUNTPOINTS_AMOUNT=$(parse_xml "install_location" "get_amount_of_new_mountpoints")
echo -e "${YELLOW}Количество новых точек монтирования:${NC} $NEW_MOUNTPOINTS_AMOUNT"

for ((i=0; i<$NEW_MOUNTPOINTS_AMOUNT; i++)); do
    NEW_MOUNTPOINT=$(parse_xml "install_location" "get_new_mountpoint" "$i")
    CURRENT_POINT_NAME="new_point$i"
    declare -A "$CURRENT_POINT_NAME"
    #получаем ассоциативный массив из строки
    eval "$CURRENT_POINT_NAME=$NEW_MOUNTPOINT"
    NEW_MOUNTPOINTS+=("$CURRENT_POINT_NAME")
done

#3) проходимся по массиву точек монтирования, открываем крипто-контейнеры,
# в которых уже есть существующая структура
# в новом формате xml-файла тег names будет полностью изъят,
# вместо него будет использоваться обязательный тег device и опциональные теги subvolume и pv-volume
# для btrfs и pv внутри luks соответственно
# пишем код как будто то бы тега names уже больше не существует

# ассоциативный массив, который хранит строки с описанием запланированных изменений
declare -A pending_commands_description


for row in "${NEW_MOUNTPOINTS[@]}"; do
    declare -n current_row="$row"  # Используем ссылку на ассоциативный массив по его имени
    #получает короткие алиасы переменных и xml-файла
    mount_point=${current_row["mount_point"]}
    type=${current_row["type"]}
    crypt_mode=${current_row["crypt_mode"]}
    
    if [[ "$i" -eq 0 && "$mount_point" != "/" ]]; then
        echo -e "${RED}Критическая ошибка: первой в $XML_FILE в разделе с точками монтирования должна быть /${NC}" >&2
        exit 1
    fi

    #device=${current_row["device"]} #device выпилен из xml-файла
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
                "file")
                    # пояснение: пока не делаем что либо, то тех пор пока
                    #пользователь подтвердит начало установки, до этого измененения на диск мы не вносим
                    #будем использовать функцию для создания и открытия крипто-контейнера
                    #create_and_open_crypt_container_by_file "$ext4_partition" "$keyfile"
                    #запишим в качестве девайса для операций, то что ранее было записано функцией save_crypt_container_info
                    #которая была вызвана внутри create_and_open_crypt_container_by_file
                    pending_commands_description["$basename_of_ext4_partition"]="Будет отформатировано в LUKS, с ext4 внутри для точки монтирования $mount_point"
 
                    ;;
                "pwd")
                    #будем использовать функцию для создания и открытия крипто-контейнера
                    #create_and_open_crypt_container_with_new_pwd "$ext4_partition"
                    #сохраним открытый крипто-контейнер в качестве девайса для операций
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
            #т.к. названия группы томов и логического тома ожидается получить от пользователя, то в данном случае
            #в качестве девайса для операций будет использоваться то, что указал пользователь, а не открытый крипто-контейнер
            #lvm в данном случае сам всё найдёт по имени группы томов, которой принадлежит в физический том из крипто-контейнера
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
                "none_in_file")
                    : #эти случаи уже были обработаны в if'ах
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_pwd")
                    : #эти случаи уже были обработаны в if'ах
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "file_in_none")
                    #пока что можно просто проверить есть ли свободное место,
                    #это можно спокойно сделать именно на данном этапе
                    #если свободного места нет, то пользователь получит соответствующее сообщение

                    #в этих двух случаях нужно будет создать новые крипто-контейнеры заданного размера
                    # TODO: пока что просто отбражаем пользователю планируемые изменения
                    # но не создаём ничего нового
                    #получаем путь к файлу-ключу
                    #keyfile=${current_row["keyfile"]}
                    #получаем размер тома
                    #lv_basename=$(get_device_basename4lsblk "$lv_name")
                    pending_commands_description["$lv_name"]="Будет создан логический том $lv_basename в группе томов $vg_name размером $size_of_lv"

                   # v эти строки нужно будет перенести в ту часть скрипта,
                   # в которой будет уже непосредственная установка
                   # #получаем имя тома и группы томов через функции
                   # lv_basename=$(get_lv_name_from_fulldevname "$lv_name")
                   # vg_name=$(get_vg_name_from_fulldevname "$lv_name")
                   # #создаём логический том заданного размера size_of_lv
                   # lvcreate -l "$size_of_lv" -n "$lv_basename" "$vg_name"
                   # #создаём крипто-контейнер и открываем его
                   # #используем функцию для создания и открытия крипто-контейнера
                   # create_and_open_crypt_container_by_file "$lv_name" "$keyfile"
                   # #сохраняем открытый крипто-контейнер в качестве девайса для операций
                   # current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                   # 
                    ;;
                "pwd_in_none")
                    #size_of_lv=${current_row["size"]}
                    #lv_basename=$(get_device_basename4lsblk "$lv_name")
                    pending_commands_description["$lv_name"]="Будет создан логический том $lv_basename в группе томов $vg_name размером $size_of_lv"
                    #используем функцию для открытия крипто-контейнера
                    #open_crypt_container_by_pwd "$lv_name"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    #current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
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

# Обновляем первый временный файл и обнуляем второй
mv $LSBLK_RAW_INFO_UPDATED $LSBLK_RAW_INFO
#выводим содержимое временного файла
# Настраиваем специальный pager для bat
#bat --style=grid,numbers \
#    --paging=always \
#    --pager="less -R -F -X -P ' ↑↓ прокрутка | q — выход'" \
#    "$LSBLK_RAW_INFO"
##Пояснение:
#- `--paging=always` принудительно пускает вывод через `less`.
#- Флаг `-F` у `less` заставляет сразу выйти, если всё влезло в экран (аналог `--quit-if-one-screen`).
#- `-X` предотвращает очистку экрана при выходе.
#- Остальные опции (`-R`, `-P`) задают цветной вывод и подсказку пользователю как выйти только в случае большого вывода.

#т.к. bat нет на установочном диске, на случай проблем с установкой будем использовать less
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

# получаем от пользователя остальные параметры, если они не были переданы в скрипт
if [[ -z "$SOFTPACK_ID" ]]; then
    SOFTPACK_ID=$(request_component_id "softpack" "Введите ID устанавливаемого набора софта")
else
    # если уже задан значит было получено из ключа -s
    # проверяем существует ли указанный набор софта
    if ! check_softpack_exists "$SOFTPACK_ID"; then
        echo -e "${RED}Указанный через ключ -s набор софта '$SOFTPACK_ID' не найден в файле ${GREEN}$XML_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}Используем указанный набор софта из ключа -s: $SOFTPACK_ID${NC}"
fi

if [[ -z "$DRIVERS_ID" ]]; then
    DRIVERS_ID=$(request_component_id "driverspack" "Введите ID устанавливаемого набора драйверов")
else
    # если уже задан значит было получено из ключа -d
    # проверяем существует ли указанный набор драйверов
    if ! check_driverspack_exists "$DRIVERS_ID"; then
        echo -e "${RED}Указанный через ключ -d набор драйверов '$DRIVERS_ID' не найден в файле ${GREEN}$XML_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}Используем указанный набор драйверов из ключа -d: $DRIVERS_ID${NC}"
fi

if [[ -z "$SETTINGS_ID" ]]; then
    SETTINGS_ID=$(request_component_id "settings" "Введите ID настроек")
else
    # если уже задан значит было получено из ключа -o
    # проверяем существует ли указанные настройки
    if ! check_settings_exists "$SETTINGS_ID"; then
        echo -e "${RED}Указанные через ключ -o настройки '$SETTINGS_ID' не найдены в файле ${GREEN}$XML_FILE${NC}"
        exit 1
    fi
    echo -e "${GREEN}Используем указанные настройки из ключа -o: $SETTINGS_ID${NC}"
fi

# откуда устанавливается система
if [[ $(parse_xml install_location get_tweak_iso) == "true" ]]; then
    INSTALL_FROM="iso"
else
    INSTALL_FROM="other_system"
fi



#создаём временный каталог для монтирования системы
#INST_DIR=$(mktemp -d)
#добавляем к имени каталога текущую дату и время для уникальности
INST_DIR="/mnt/system_installing_$(date +%Y-%m-%d_%H-%M)"
mkdir -p $INST_DIR 
#проверка, что этот каталог не смонтирован
if mount | grep -q $INST_DIR; then
    echo "Ошибка: каталог $INST_DIR уже смонтирован" >&2
    exit 1
fi



# случаи для legacy будут добавлены потом
EFI_DEV="$(parse_xml install_location get_efi_dev)"
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
                    current_row["device_for_operation"]=$current_row["opened_crypt_container_fullname"]
                    ;;
                "file")
                    create_and_open_crypt_container_with_file ${current_row["device"]} ${current_row["keyfile"]}
                    #получаем имя раздела для монтирования
                    current_row["device_for_operation"]=$current_row["opened_crypt_container_fullname"]
                    ;;
            esac
            #форматируем раздел
            mkfs.ext4 ${current_row["device_for_operation"]}
            #создаём каталог $INST_DIR$mount_point если он не существует
            mkdir -p $INST_DIR$mount_point
            #монтируем раздел
            mount ${current_row["device_for_operation"]} $INST_DIR$mount_point
            ;;
        "new_subvol_in_btrfs" | "new_subvol_in_btrfs_in_lvm")
            #в обоих этих случаях набор операций идентичен
            #в этих случаях поле device_for_operation уже получено
            #в предыдущем цикле для всех опций шифрования
            btrfs_device=${current_row["device_for_operation"]}
            subvol_name=${current_row["subvolume"]}
            #создаём подтом
            btrfs subvolume create "${ALL_BTRFS_MOUNTPOINTS["$btrfs_device"]}/$subvol_name"
            #создаём каталог $INST_DIR$mount_point если он не существует
            mkdir -p $INST_DIR$mount_point
            #монтируем подтом в каталог установки (внутри chroot'а)
            mount -o subvol=$subvol_name $btrfs_device $INST_DIR$mount_point
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
            lvcreate -L $size_of_lv -n $lv_basename $vg_name
            #создаём каталог $INST_DIR$mount_point если он не существует
            mkdir -p $INST_DIR$mount_point
            case $crypt_mode in
                "none_in_none" | "none_in_pwd" | "none_in_file")
                    #в этих случаях поле device_for_operation уже получено
                    :
                    ;;
                "pwd_in_none")
                    #используем функцию для создания и открытия крипто-контейнера
                    create_and_open_crypt_container_with_new_pwd "$lv_name"
                    #получаем имя раздела для монтирования
                    current_row["device_for_operation"]=$current_row["opened_crypt_container_fullname"]
                    ;;
                "file_in_none")
                    #используем функцию для создания и открытия крипто-контейнера
                    create_and_open_crypt_container_with_file "$lv_name" "$current_row["keyfile"]"
                    #получаем имя раздела для монтирования
                    current_row["device_for_operation"]=$current_row["opened_crypt_container_fullname"]
                    ;; 
            esac
            #монтируем том lvm или содержимое контейнера luks в каталог установки (внутри chroot'а)
            mount $current_row["device_for_operation"] $INST_DIR$mount_point
            ;;
    esac

done


#монтируем EFI-раздел
mkdir -p $INST_DIR/$EFI_NEW_LOCATION
mount $EFI_DEV $INST_DIR/$EFI_NEW_LOCATION

# Установка основных пакетов
pacstrap $INST_DIR $SOFT_PACK1

# Генерация fstab
genfstab -U $INST_DIR >> $INST_DIR/etc/fstab

#если массив CRYPT_VOLUMES существует
if [[ -v CRYPT_VOLUMES[@] ]]; then
    for ((i=0; i<${#CRYPT_VOLUMES[@]}; i++)); do
        lv_name="${CRYPT_VOLUMES[i]}"
        #Настройка зашифрованного раздела
        echo "cryptroot UUID=$(blkid -s UUID -o value $lv_name) none luks" >> $INST_DIR/etc/crypttab
        echo "GRUB_CMDLINE_LINUX=\"cryptdevice=$lv_name:cryptroot root=/dev/mapper/cryptroot\"" >> $INST_DIR/etc/default/grub

    done
fi

#копирование дополнительных файлов, для выполнения внутри системы (должны быть в одном каталоге с этим)
cp $SCRIPT_DIR/$CHROOT_SCRIPT $INST_DIR
cp $SCRIPT_DIR/$XML_PARSER $INST_DIR
cp $SCRIPT_DIR/$XML_FILE $INST_DIR

#получаем список архивов для распаковки в домашнюю папку пользователя
ARCHIVES_4HOME="$(parse_xml softpack get_archs4home)"

#копирование и распоковка архивов с файлами для домашнего каталога (будут распаковываны в chroot'е)
for archive in $ARCHIVES_4HOME; do
    cp $SCRIPT_DIR/$archive $INST_DIR
done

#-------------------------------
# Chroot в новую систему
# передаём в скрипт idшники установки и имя загрузчика в EFI-разделе
arch-chroot $INST_DIR /bin/bash -c "/run_inside_chroot.sh \"$SOFTPACK_ID\" \"$DRIVERSPACK_ID\" \"$INSTALL_LOCATION_ID\" \"$SETTINGS_ID\" \"$EFI_SYS_NAME\""
#-------------------------------

#удаляем выполнившуюся в chroot'е копию второго скрипта
rm $INST_DIR/$CHROOT_SCRIPT
rm $INST_DIR/$XML_PARSER
rm $INST_DIR/$XML_FILE


#размонтируем раздел EFI
umount $INST_DIR/$EFI_NEW_LOCATION

# Размонтирование всех разделов
umount -R $INST_DIR
if [ -z "$(ls -A $INST_DIR)" ]; then
    rmdir $INST_DIR
else
    echo -e "${RED}Каталог $INST_DIR не пустой. Удаление не выполнено.${NC}"
fi

echo -e "${GREEN}ALL DONE${NC}"


if [[ $INSTALL_FROM == "other_system" ]]; then
    echo "не забудь выполнить grub-mkconfig -o /boot/grub/grub.cfg (если нужно)"
    read -p "Нажмите Enter для выхода..."
else
    echo "Установка завершена. Перезагрузите компьютер."
fi