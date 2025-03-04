#!/usr/bin/python3  
import sys
import xml.etree.ElementTree as ET


def main():
    if len(sys.argv) < 2:
        print("Использование: python get_data_from_componets_xml.py <тип компонента> <id компонента> <команда> [дополнительные аргументы]")
        print("Или для получения списка компонентов: python get_data_from_componets_xml.py list_<тип компонента>")
        print("Типы компонентов: driverspack, softpack, install_location, settings")
        sys.exit(1)
    
    # Проверяем, если команда для получения списка компонентов
    if sys.argv[1].startswith('list_'):
        component_type = sys.argv[1].replace('list_', '')
        # Парсим XML-файл
        tree = ET.parse('components.xml')
        root = tree.getroot()
        
        # Получаем все 'name' компонентов выбранного типа
        if component_type == 'driverspack' or component_type == 'driverspacks':
            components = [comp.get('name') for comp in root.findall('driverspacks/driverspack')]
        elif component_type == 'softpack' or component_type == 'softpacks':
            components = [comp.get('name') for comp in root.findall('softpacks/softpack')]
        elif component_type == 'install_location' or component_type == 'install_locations':
            components = [comp.get('name') for comp in root.findall('install_locations/install_location')]
        elif component_type == 'settings' or component_type == 'settings_variants':
            components = [comp.get('name') for comp in root.findall('settings_variants/settings')]
        else:
            print(f"Неизвестный тип компонента '{component_type}'")
            sys.exit(1)
            
        print(' '.join(components))
        sys.exit(0)
    
    # В остальных случаях ожидаем тип компонента, id и команду
    if len(sys.argv) < 4:
        print("Использование: python get_data_from_componets_xml.py <тип компонента> <id компонента> <команда> [дополнительные аргументы]")
        sys.exit(1)
        
    component_type = sys.argv[1]
    component_id = sys.argv[2]
    command = sys.argv[3]
    optional_args = sys.argv[4:]
    
    # Парсим XML-файл
    tree = ET.parse('components.xml')
    root = tree.getroot()
    
    # Находим компонент по типу и ID
    component = None
    
    if component_type == 'driverspack' or component_type == 'driverspacks':
        for comp in root.findall('driverspacks/driverspack'):
            if comp.get('name') == component_id:
                component = comp
                break
    elif component_type == 'softpack' or component_type == 'softpacks':
        for comp in root.findall('softpacks/softpack'):
            if comp.get('name') == component_id:
                component = comp
                break
    elif component_type == 'install_location' or component_type == 'install_locations':
        for comp in root.findall('install_locations/install_location'):
            if comp.get('name') == component_id:
                component = comp
                break
    elif component_type == 'settings' or component_type == 'settings_variants':
        for comp in root.findall('settings_variants/settings'):
            if comp.get('name') == component_id:
                component = comp
                break
    else:
        print(f"Неизвестный тип компонента '{component_type}'")
        sys.exit(1)
        
    if component is None:
        print(f"Компонент с id '{component_id}' типа '{component_type}' не найден.")
        sys.exit(1)
    
    # Обработка команды
    if command == 'get_pkgs_pacstrap':
        pacstrap_elem = component.find('pakages/pacstrap')
        if pacstrap_elem is not None:
            print(pacstrap_elem.text.strip())
        else:
            print("")
    elif command == 'get_pkgs_pacman':
        bundles = component.findall('pakages/bundle')
        pkgs = []
        for bundle in bundles:
            if bundle.text and bundle.text.strip():
                pkgs.extend(bundle.text.strip().split())
        print(' '.join(pkgs))
    elif command == 'get_hooks':
        hooks_elem = component.find('hooks')
        if hooks_elem is not None:
            print(hooks_elem.text.strip())
        else:
            print("")
    elif command == 'get_archs4home':
        archives = component.findall('extrafiles/home/archive')
        archive_names = [archive.text.strip() for archive in archives if archive.text]
        print(' '.join(archive_names))
    elif command == 'get_amount_of_new_mountpoints':
        points = component.findall('mountpoints/point[@type="new"]')
        print(len(points))
    elif command == 'get_amount_of_extra_mountpoints':
        points = component.findall('mountpoints/point[@type="extra"]')
        print(len(points))
    elif command == 'get_new_mountpoint':
        if len(optional_args) < 1:
            print("Пожалуйста, укажите индекс для get_new_mountpoint")
            sys.exit(1)
        index = int(optional_args[0])
        points = component.findall('mountpoints/point[@type="new"]')
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
            print("Пожалуйста, укажите индекс для get_extra_mountpoint")
            sys.exit(1)
        index = int(optional_args[0])
        points = component.findall('mountpoints/point[@type="extra"]')
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
        timezone_elem = component.find('timezone')
        if timezone_elem is not None:
            print(timezone_elem.text.strip())
        else:
            print("")
    elif command == 'get_hostname':
        hostname_elem = component.find('hostname')
        if hostname_elem is not None:
            print(hostname_elem.text.strip())
        else:
            print("")
    elif command == 'get_username':
        username_elem = component.find('username')
        if username_elem is not None:
            print(username_elem.text.strip())
        else:
            print("")
    elif command == 'get_useruid':
        useruid_elem = component.find('useruid')
        if useruid_elem is not None:
            print(useruid_elem.text.strip())
        else:
            print("")
    elif command == 'get_locales':
        locales = component.findall('locales/locale')
        locales_list = [locale.text.strip() for locale in locales if locale.text]
        print('#'.join(locales_list))
    elif command == 'get_default_locale':
        default_locale_elem = component.find('locales/default')
        if default_locale_elem is not None:
            print(default_locale_elem.text.strip())
        else:
            print("")
    elif command == 'get_vconsole_strings':
        vconsole_strings = component.findall('locales/vconsole_add')
        vconsole_strings_list = [vconsole_string.text.strip() for vconsole_string in vconsole_strings if vconsole_string.text]
        print('#'.join(vconsole_strings_list))
    elif command == 'get_efi_bootlabel':
        bootlabel_elem = component.find('efi/bootlabel')
        if bootlabel_elem is not None:
            print(bootlabel_elem.text.strip())
        else:
            print("")
    elif command == 'get_efi_dev':
        dev_elem = component.find('efi/dev')
        if dev_elem is not None:
            print(dev_elem.text.strip())
        else:
            print("")
    elif command == 'get_efi_new_location':
        new_location_elem = component.find('efi/new_location')
        if new_location_elem is not None:
            print(new_location_elem.text.strip())
        else:
            print("")
    elif command == 'get_tweak_iso':
        iso_elem = component.find('iso')
        if iso_elem is not None:
            print(iso_elem.text.strip())
        else:
            print("")
    elif command == 'get_init_system':
        init_system_elem = component.find('init_system')
        if init_system_elem is not None:
            print(init_system_elem.text.strip())
        else:
            print("")
    elif command == 'get_softpack_tweaks':
        tweaks_elem = component.find('softpack_tweaks')
        if tweaks_elem is not None and tweaks_elem.text:
            print(tweaks_elem.text.strip())
        else:
            print("")
    elif command == 'get_aur_packages':
        aur_elem = component.find('pakages/aur')
        if aur_elem is not None and aur_elem.text:
            print(aur_elem.text.strip())
        else:
            print("")
    elif command == 'get_flatpak_packages':
        flatpak_elem = component.find('pakages/flatpak')
        if flatpak_elem is not None and flatpak_elem.text:
            print(flatpak_elem.text.strip())
        else:
            print("")
    elif command == 'get_description':
        # Получаем атрибут description
        description = component.get('description')
        
        if description is not None and description.strip():
            print(description.strip())
        else:
            print("Описание отсутствует")
    else:
        print(f"Неизвестная команда '{command}'")
        sys.exit(1)

if __name__ == '__main__':
    main()
