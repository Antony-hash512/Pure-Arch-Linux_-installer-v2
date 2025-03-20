#!/bin/bash

# Заранее вычисленные степени 1024
MB=1048576  # 1024^2
GB=1073741824  # 1024^3
TB=1099511627776  # 1024^4
PB=1125899906842624  # 1024^5
EB=1152921504606846976  # 1024^6

# Стоковые константы
AUTODIR="autocreated_scripts"
XML_FILE="components.xml"
XML_PARSER="get_data_from_components_xml.py"
CHROOT_SCRIPT="run_inside_chroot.sh"
