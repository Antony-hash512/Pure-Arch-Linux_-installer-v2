#!/bin/bash

#задаём степень сжатия
COMPRESSION_LEVEL=$1
#задаём значение по умолчанию
if [ -z "$COMPRESSION_LEVEL" ]; then
    COMPRESSION_LEVEL=9
fi

export ZSTD_CLEVEL=$COMPRESSION_LEVEL

FILES_ARCH_DIR="./tar.zst-s_contents_$RANDOM"

# создаём массив с именами архивов
ARCH_NAMES=()

# получаем список архивов
for file in *.tar.zst; do
    # удаляем расширение .tar.zst
    file=$(echo "$file" | sed 's/\.tar\.zst$//')
    ARCH_NAMES+=("$file")
    mkdir -p "$FILES_ARCH_DIR/$file"
done

# распаковываем архивы
for ARCH_NAME in "${ARCH_NAMES[@]}"; do
    tar --no-same-owner -xvf "$ARCH_NAME".tar.zst -C "$FILES_ARCH_DIR/$ARCH_NAME"
done




