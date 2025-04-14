#!/bin/sh
# тут будет болванка для установочного скрипта
# пока что пишу код, который все проверяет перед установкой
# и всё наглядно отображает пользователю
# когда он будет готов, то начну работать над самим установочным скриптом
#0) проверяем на права суперпользователя и версию баша
#1) задаём различные переменные и константы
#1.1) проверяем кириллический шрифт (будет убрано в англ.версии)
#1.2) устанавливаем необходимые пакеты
#2) получаем от пользователя данные какие компоненты использовать
#2.1) получаем данные и xml-файла
#2.2) проверяем корректность данных в xml-файле (задача на потом, пока что работаем с заведомо корректними данными)
#3) проходимся по массиву точек монтирования, открываем крипто-контейнеры, в которых уже есть существующая
#структура на этом же этапе обрабатываем 3 вида ошибок
#4) взяв за основу вывод команду lsblk отображаем пользователя информацию о:
#  * уже существующих поддомах на btrfs
#  * поддома btrfs, которые планируются к созданию (и какая точка мониторования планируется к привязке)
#  * логические тома lvm, которые планируются к созданию (+ точки монирования)
#  * крипто-контейны, luks, которые планируются к созданию и что в них планируется разместить
#  * существующий проблемах, например нехватки свободного место и т.д.
: <<'TODO'
* лучше перейти на партишены по uuid: теги device нужно разграничить на <lv-volume> и <uuid>
* нужно добавить функции, которые проверяют: 1) существование партишна по uuid, 2) существования группы томов
* перенести логику вывода информации пользователю (нужно подумать оставить ли 
её в том виде, ли тот код нужно переделать)
* создать функцию, которая будет проверять корректность данных в xml-файле
* создать функции, которые будут проверять хватает ли свободного места
реализоцию можно посмотреть в prev_ver_of_install.sh одну для сабволюмов btrfs, другую для lvm
* добавить обработку всех возможных проблем, которые могут возникнуть

Другие TODO находятся в файлах prev_ver_of_install.sh и part_info_test.sh
их я перенесу сюда, когда закончу с этой болванкой путем переноса сюда всех нароботок
TODO
# проверяем версию баша
echo "Bash version: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]}"
echo ""
if (( BASH_VERSINFO[0] > 4 )) || { (( BASH_VERSINFO[0] == 4 )) && (( BASH_VERSINFO[1] > 3 )); }; then
    :
else
    echo "The required version of Bash is 4.3 or higher" >&2
    exit 1
fi

#проверяем на права суперпользователя
if [[ "$EUID" -ne 0 ]]; then
    echo -e "\033[31mERROR: This script must be run as root\033[0m" >&2
    exit 1
fi


#1) задаём различные переменные и константы
# Подключаем файл с цветовыми переменными
source include/colors.sh
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

# создаём ассоциативный массив problems для возможного запланированного выхода 
declare -A problems
#вносим значения в массив (пустая строка - означает, что проблемы нет)
problems["no_free_space"]="" 
problems["btrfs_subvolume_name_already_exists"]=""
problems["lvm_logical_volume_name_already_exists"]=""
problems["btrfs_device_not_found"]="" # эти три проблемы можно чекнуть на этапе открытия крипто-контейнеров (1)
problems["lvm_group_not_found"]="" #(2)
problems["ext4_device_not_found"]="" #(3)
problems["syntax_problem_in_xml_file"]=""

#флаг для запланрованного выхода из скрипта
exit_and_show_problems_flag=0

#создаём ассоциативный массив, который будет находить хотя бы одну точку монтирования по имени устройства btrfs
declare -A ALL_BTRFS_MOUNTPOINTS

#создаём ассоциативный массив, который будет хранить имена открытых крипто-контейнеров
declare -A OPENED_CRYPT_CONTAINERS

#создаём массив для хранения имен новых точек монтирования
declare -a NEW_MOUNTPOINTS

#1.1) проверяем кириллический шрифт (будет убрано в англ.версии)
echo "test тест"
echo "если этот текст можно прочитать, то можно продолжать без смены шрифта"
echo "Do you want to switch to a font with Cyrillic support? (Y/n)"
read -r USE_CYRILLIC_FONT
if [[ -z "$USE_CYRILLIC_FONT" || "$USE_CYRILLIC_FONT" =~ ^[Yy]$ ]]; then
    setfont cyr-sun16
    echo "test тест"
    echo "была использована команда setfont cyr-sun16"
    echo "if it doesn't work, you can use Ctrl+C to exit and to solve this problem by another way"
else
    echo "Остаемся на стандартном шрифте (if the cyrillic font doesn't work, you can use Ctrl+C to exit)"
fi
#далее считается что кириллица поддерживается (ведем диалог с пользователем на русском, английская версия будет реализована позже, пока что нет смысла)
echo "перед использованием скрипта также должен быть настроен доступ в интернет и выпонена необходимая минимальная разбивка разделов на диске"
read -p "Enter - продолжить; ctrl+C - прервать"

#1.2) устанавливаем необходимые пакеты
pacman -Sy
packages=("arch-install-scripts" "terminus-font" "base" "lvm2" "cryptsetup" "btrfs-progs" "efibootmgr" "python" "bc")

for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        sudo pacman -S "$pkg" --noconfirm
    fi
done
# "lvm2" "cryptsetup" "btrfs-progs" - можно установливать позже по мере необхотмости но пока прописаны здесь
# почти все простые вещи входят в base, а именно grep, sed, util-linux для lsblk, coreutils для date
# можно автоматически определять есть ли хоть где-нибудь шифрование или (очень пригодится в финальной части скрипта)



#2) получаем от пользователя данные какие компоненты использовать
# Обработка аргументов командной строки
INSTALL_LOCATION_ID=""
while getopts "i:" opt; do
  case $opt in
    i)
      # Проверяем существует ли указанное значение install_location
      if check_install_location_exists "$OPTARG"; then
        INSTALL_LOCATION_ID="$OPTARG"
        echo -e "${GREEN}Используем указанное место установки: $INSTALL_LOCATION_ID${NC}"
      else
        echo -e "${RED}Указанное место установки '$OPTARG' не найдено${NC}"
      fi
      ;;
    \?)
      echo -e "${RED}Неверный параметр -$OPTARG${NC}" >&2
      ;;
  esac
done

# Если INSTALL_LOCATION_ID не был задан через ключ -i или указанное значение не найдено
if [[ -z "$INSTALL_LOCATION_ID" ]]; then
    # Выбор места установки
    INSTALL_LOCATION_ID=$(request_component_id "install_location" "Введите ID места установки")
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
    device=${current_row["device"]}
    #в каждый кейс прописан подкейс с опциями шифрования
    #устройства с которыми будут проводиться операции будет внесено в поле current_row["device_for_operations"]
    #за исключением случаев, когда крипто-контейнер ещё только нужно будет создать
    #в этих случаях заполнение этого поля будет происходить позже, на внесения измениний
    #данное поле содержать или открытый luks или продублированное имя устройства, если шифрование не используется
    case "$type" in
        "format_ext4")
            #в данном случае задан только партишн, который будет форматироваться
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
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
        "new_subvol_in_btrfs")
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
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
       "new_subvol_in_btrfs_in_lvm")
            subvol_name=${current_row["subvolume"]}
            #получаем имя группы томов
            vg_name=$(get_vg_name_from_fulldevname "$device")
            
            lv_name=$device
            btrfs_device=$lv_name #аллиас т.к. по смыслу это одно тоже          
            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device=${cureent_row["pv-volume"]}
                    #т.к. названия группы томов и логического тома ожидается получить от пользователя, то в данном случае
                    #в качестве девайса для операций будет использоваться то, что указал пользователь, а не открытый крипто-контейнер
                    #lvm в данном случае сам всё найдёт по имени группы томов, которой принадлежит в физический том из крипто-контейнера
                    #при этом пользователя надо предупредить о возможной дыре в безопасности, 
                    #если в этой группе томов присутствует хотя бы один физический том, который не зашифрован
                    current_row["device_for_operations"]=$lv_name
                    #используем функцию для открытия крипто-контейнера
                    keyfile=${current_row["keyfile"]}
                    open_crypt_container_by_file "$pv_device" "$keyfile"
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device=${cureent_row["pv-volume"]}
                    current_row["device_for_operations"]=$lv_name
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$pv_device"
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
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            
            ;;
        "new_ext4_in_lvm")
            lv_name=$device
            #имя и группы нужно будет получить через спец. функции, которые работают через регексы и учитывают запись через mapper
            #vg_name=$(echo "$lv_name" | awk -F/ '{print $3}')  # Получаем имя группы томов

            #пока что пишем тут команды как будто бы всё было бы сделано сразу, потом закоментируем для откладывания на потом

            size_of_lv=${current_row["size"]}
            case "$crypt_mode" in
                "none_in_none")
                    current_row["device_for_operations"]=$lv_name
                    ;;
                "none_in_file")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device=${current_row["pv-volume"]}
                    #используем функцию для открытия крипто-контейнера
                    keyfile=${current_row["keyfile"]}
                    open_crypt_container_by_file "$pv_device" "$keyfile"
                    #opened_lvm_device=${current_row["opened_crypt_container_fullname"]}
                    ;;
                "none_in_pwd")
                    #в таком режиме от пользователя также требуется указать партишн с luks в котором лежит pv lvm
                    pv_device=${current_row["pv-volume"]}
                    #используем функцию для открытия крипто-контейнера
                    open_crypt_container_by_pwd "$pv_device"
                    ;;
                "file_in_none")
                    #в этих двух случаях нужно будет создать новые крипто-контейнеры заданного размера
                    # TODO: пока что просто отбражаем пользователю планируемые изменения
                    # но не создаём ничего нового
                    #получаем путь к файлу-ключу
                    #keyfile=${current_row["keyfile"]}
                    #получаем размер тома
                    size_of_lv=${current_row["size"]}
                    lv_basename=$(get_device_basename4lsblk "$lv_name")
                    pending_commands_description["$lv_basename"]="Будет создан логический том $lv_basename в группе томов $vg_name размером $size_of_lv"

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
                    size_of_lv=${current_row["size"]}
                    lv_basename=$(get_device_basename4lsblk "$lv_name")
                    pending_commands_description["$lv_basename"]="Будет создан логический том $lv_basename в группе томов $vg_name размером $size_of_lv"
                    #используем функцию для открытия крипто-контейнера
                    #open_crypt_container_by_pwd "$lv_name"
                    #сохраняем открытый крипто-контейнер в качестве девайса для операций
                    #current_row["device_for_operations"]=${current_row["opened_crypt_container_fullname"]}
                    ;;
                *)
                    echo "Неизвестный тип: $crypt_mode" >&2
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Неизвестный тип: $type" >&2
            exit 1
            ;;
    esac
    
done
 