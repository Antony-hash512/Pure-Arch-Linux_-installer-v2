#/bin/sh

#задаём степень сжатия
COMPRESSION_LEVEL=$2
#задаём значение по умолчанию
if [ -z "$COMPRESSION_LEVEL" ]; then
    COMPRESSION_LEVEL=9
fi

export ZSTD_CLEVEL=$COMPRESSION_LEVEL

INPUT_ARCH=$1

INPUT_ARCH_BASENAME=$(echo "$INPUT_ARCH" | sed 's/\.tar\..*//')

if [ ! -f "$INPUT_ARCH" ]; then
    echo "Input archive not found"
    exit 1
fi

if [ -f "${INPUT_ARCH_BASENAME}.tar.zst" ]; then
    echo "Output archive already exists"
    exit 1
fi


#создаем временную директорию
TEMP_DIR=$(mktemp -d)

#распаковываем архив
tar --no-same-owner -xvf "$INPUT_ARCH" -C "$TEMP_DIR"

#если версия tar больше 1.31, то перепаковываем архив в zstd напрямую без внешнего компрессора
TAR_VERSION=$(tar --version | grep -oP 'tar \(GNU tar\) \K[\d.]+')
# Обрезаем версию до major.minor (убираем всё после второй точки)
TAR_VERSION=$(echo "$TAR_VERSION" | grep -oP '^\d+\.\d+')
echo "Tar version: $TAR_VERSION"
# Сравниваем версии как числа с плавающей точкой через bc
if [ "$(echo "$TAR_VERSION > 1.31" | bc)" -eq 1 ]; then
    echo "using directly compression"
    tar --zstd --numeric-owner -cvf "${INPUT_ARCH_BASENAME}.tar.zst" -C "$TEMP_DIR" .
else
    echo "using an external compressor"
    tar -I zstd --numeric-owner -cvf "${INPUT_ARCH_BASENAME}.tar.zst" -C "$TEMP_DIR" .
fi

#удаляем временную директорию
rm -rf "$TEMP_DIR"

