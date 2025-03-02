#!/bin/bash
ALL_DRIVERS_PACKS="$(python3 get_data_from_componets_xml.py list_driverspacks)"
ALL_SOFT_PACKS="$(python3 get_data_from_componets_xml.py list_softpacks)"
ALL_INSTALL_LOCATIONS="$(python3 get_data_from_componets_xml.py list_install_locations)"
ALL_SETTINGS_VARIANTS="$(python3 get_data_from_componets_xml.py list_settings_variants)"

echo "В файле components.xml найдены следующие драйверные паки:"
for drv in $ALL_DRIVERS_PACKS; do
    description=$(python3 get_data_from_componets_xml.py driverspack "$drv" get_description)
    echo "  $drv - $description"
done

echo -e "\nВ файле components.xml найдены следующие программные паки:"
for soft in $ALL_SOFT_PACKS; do
    description=$(python3 get_data_from_componets_xml.py softpack "$soft" get_description)
    echo "  $soft - $description" 
done
