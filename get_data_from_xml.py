#!/user/bin/python
import sys
import xml.etree.ElementTree as ET

def main():
    if len(sys.argv) < 2:
        print("Использование: python get_data_from_xml.py <system_id> <command> [дополнительные аргументы]")
        print("Или для получения списка систем: python get_data_from_xml.py list_system_ids")
        sys.exit(1)
    
    # Проверяем, если команда 'list_system_ids'
    if sys.argv[1] == 'list_system_ids':
        # Парсим XML-файл
        tree = ET.parse('systems.xml')
        root = tree.getroot()
        # Получаем все 'id' систем
        system_ids = [sys_elem.get('id') for sys_elem in root.findall('system')]
        print(' '.join(system_ids))
        sys.exit(0)
    
    # В остальных случаях ожидаем, что первый аргумент - это 'system_id'
    system_id = sys.argv[1]
    if len(sys.argv) < 3:
        print("Использование: python get_data_from_xml.py <system_id> <command> [дополнительные аргументы]")
        sys.exit(1)
    command = sys.argv[2]
    optional_args = sys.argv[3:]

    # Парсим XML-файл
    tree = ET.parse('systems.xml')
    root = tree.getroot()

    # Находим систему по ID
    system = None
    for sys_elem in root.findall('system'):
        if sys_elem.get('id') == system_id:
            system = sys_elem
            break
    if system is None:
        print(f"Система с id '{system_id}' не найдена.")
        sys.exit(1)
    
    # Обработка команды
    if command == 'get_pkgs_pacstrap':
        pacstrap_elem = system.find('pakages/pacstrap')
        if pacstrap_elem is not None:
            print(pacstrap_elem.text.strip())
        else:
            print("")
    elif command == 'get_pkgs_pacman':
        bundles = system.findall('pakages/bundle')
        pkgs = []
        for bundle in bundles:
            pkgs.extend(bundle.text.strip().split())
        print(' '.join(pkgs))
    elif command == 'get_hooks':
        hooks_elem = system.find('hooks')
        if hooks_elem is not None:
            print(hooks_elem.text.strip())
        else:
            print("")
    elif command == 'get_archs4home':
        archives = system.findall('extrafiles/home/archive')
        archive_names = [archive.text.strip() for archive in archives]
        print(' '.join(archive_names))
    elif command == 'get_amount_of_new_mountpoints':
        points = system.findall('mountpoints/point[@type="new"]')
        print(len(points))
    elif command == 'get_amount_of_extra_mountpoints':
        points = system.findall('mountpoints/point[@type="extra"]')
        print(len(points))
    elif command == 'get_new_mountpoint':
        if len(optional_args) < 1:
            print("Пожалуйста, укажите индекс для get_new_mountpont")
            sys.exit(1)
        index = int(optional_args[0])
        points = system.findall('mountpoints/point[@type="new"]')
        if index >= len(points):
            print("Индекс выходит за пределы списка")
            sys.exit(1)
        point = points[index]
        data = {
            "mount_point": point.find('location').text.strip(),
            "type": point.find('way').text.strip(),
            "crypt_mode": point.find('crypt_mode').text.strip(),
            "name": point.find('names').text.strip()
        }
        bash_array = "(" + ' '.join([f'["{k}"]="{v}"' for k, v in data.items()]) + ")"
        print(bash_array)
    elif command == 'get_extra_mountpoint':
        if len(optional_args) < 1:
            print("Пожалуйста, укажите индекс для get_extra_mountpont")
            sys.exit(1)
        index = int(optional_args[0])
        points = system.findall('mountpoints/point[@type="extra"]')
        if index >= len(points):
            print("")
            sys.exit(1)
        point = points[index]
        data = {
            "mount_point": point.find('location').text.strip(),
            "type": point.find('way').text.strip(),
            "crypt_mode": point.find('crypt_mode').text.strip(),
            "name": point.find('names').text.strip()
        }
        bash_array = "(" + ' '.join([f'["{k}"]="{v}"' for k, v in data.items()]) + ")"
        print(bash_array)
    elif command == 'get_timezone':
        timezone_elem = system.find('settings/timezone')
        if timezone_elem is not None:
            print(timezone_elem.text.strip())
        else:
            print("")
    elif command == 'get_hostname':
        hostname_elem = system.find('settings/hostname')
        if hostname_elem is not None:
            print(hostname_elem.text.strip())
        else:
            print("")
    elif command == 'get_username':
        username_elem = system.find('settings/username')
        if username_elem is not None:
            print(username_elem.text.strip())
        else:
            print("")
    elif command == 'get_useruid':
        useruid_elem = system.find('settings/useruid')
        if useruid_elem is not None:
            print(useruid_elem.text.strip())
        else:
            print("")
    elif command == 'get_locales':
        locales = system.findall('settings/locales/locale')
        locales_list = [locale.text.strip() for locale in locales]
        print('#'.join(locales_list))
    elif command == 'get_default_locale':
        default_locale_elem = system.find('settings/locales/default')
        if default_locale_elem is not None:
            print(default_locale_elem.text.strip())
        else:
            print("")
    elif command == 'get_vconsole_strings':
        vconsole_strings = system.findall('settings/locales/vconsole_add')
        vconsole_strings_list = [vconsole_string.text.strip() for vconsole_string in vconsole_strings]
        print('#'.join(vconsole_strings_list))
    elif command == 'get_efi_bootlabel':
        bootlabel_elem = system.find('settings/efi/bootlabel')
        if bootlabel_elem is not None:
            print(bootlabel_elem.text.strip())
        else:
            print("")
    elif command == 'get_efi_dev':
        dev_elem = system.find('settings/efi/dev')
        if dev_elem is not None:
            print(dev_elem.text.strip())
        else:
            print("")
    elif command == 'get_efi_new_location':
        new_location_elem = system.find('settings/efi/new_location')
        if new_location_elem is not None:
            print(new_location_elem.text.strip())
        else:
            print("")
    elif command == 'get_tweak_iso':
        iso_elem = system.find('settings/tweaks/iso')
        if iso_elem is not None:
            print(iso_elem.text.strip())
        else:
            print("")
    elif command == 'get_tweak_openbox':
        openbox_elem = system.find('settings/tweaks/openbox')
        if openbox_elem is not None:
            print(openbox_elem.text.strip())
        else:
            print("")
    elif command == 'get_tweak_createroot':
        createroot_elem = system.find('settings/tweaks/createroot')
        if createroot_elem is not None:
            print(createroot_elem.text.strip())
        else:
            print("")
    else:
        print(f"Неизвестная команда '{command}'")
        sys.exit(1)

if __name__ == '__main__':
    main()

