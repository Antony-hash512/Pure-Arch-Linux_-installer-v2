#!/bin/bash

#задаём степень сжатия
COMPRESSION_LEVEL=$1
#задаём значение по умолчанию
if [ -z "$COMPRESSION_LEVEL" ]; then
    COMPRESSION_LEVEL=9
fi

export ZSTD_CLEVEL=$COMPRESSION_LEVEL

FILES_ARCH_DIR="tar_zsts_contents"

# создаём массив с именами архивов
ARCH_NAMES=()

# получаем список архивов
for dir_name in "$FILES_ARCH_DIR"/*/; do
    if [ -d "$dir_name" ]; then
        DIR_NAMES+=("$(basename "$dir_name")")
    fi
done

#если версия tar больше 1.31, то перепаковываем архив в zstd напрямую без внешнего компрессора
TAR_VERSION=$(tar --version | grep -oP 'tar \(GNU tar\) \K[\d.]+')
# Обрезаем версию до major.minor (убираем всё после второй точки)
TAR_VERSION=$(echo "$TAR_VERSION" | grep -oP '^\d+\.\d+')
echo "Tar version: $TAR_VERSION"

# Пакуем архивы (только для несуществующих архивов)
for DIR_NAME in "${DIR_NAMES[@]}"; do
    if [ ! -f "$DIR_NAME.tar.zst" ]; then
        # Сравниваем версии как числа с плавающей точкой через bc
        if [ "$(echo "$TAR_VERSION > 1.31" | bc)" -eq 1 ]; then
            echo "using directly compression"
            tar --zstd --numeric-owner -cvf "$DIR_NAME.tar.zst" "$FILES_ARCH_DIR/${DIR_NAME}"
        else
            echo "using an external compressor"
            tar -I zstd --numeric-owner -cvf "$DIR_NAME.tar.zst" "$FILES_ARCH_DIR/${DIR_NAME}"
        fi
    else
        echo "Archive $DIR_NAME.tar.zst was missed because it already exists."
        echo "Remove, move or rename this file if you want to repack it."
    fi 
done







