#!/bin/bash

set -euo pipefail

# === Настройки ===
SRC_MNT="/mnt/input"
SRC_SUBVOL="@arch_gnome"
DEST_MNT="/mnt/output"
DELETE_SNAPS=false  # true или false: хочешь ли удалять временные снапшоты

# === Создание read-only снапшота корневого сабволюма ===
echo "[+] Создаём снапшот $SRC_SUBVOL"
sudo btrfs subvolume snapshot -r "$SRC_MNT/$SRC_SUBVOL" "$SRC_MNT/${SRC_SUBVOL}_send"

# === Список вложенных сабволюмов ===
echo "[+] Ищем вложенные сабволюмы..."
mapfile -t SUBVOLS < <(
  sudo btrfs subvolume list -o "$SRC_MNT/$SRC_SUBVOL" \
    | sed -E 's/^.* path //' \
    | grep -v -E '(snapshots|_snap|_send)' \
    | grep -v '^\.snapshot'
)

# === Создание read-only снапшотов вложенных сабволюмов ===
for subvol_rel in "${SUBVOLS[@]}"; do
    echo "[+] Снапшот вложенного сабволюма: $subvol_rel"
    sudo btrfs subvolume snapshot -r "$SRC_MNT/$subvol_rel" "$SRC_MNT/${subvol_rel}_send"
done

# === Отправка корневого снапшота ===
echo "[+] Отправляем $SRC_SUBVOL"
sudo btrfs send "$SRC_MNT/${SRC_SUBVOL}_send" | sudo btrfs receive "$DEST_MNT"

# === Отправка вложенных сабволюмов ===
for subvol_rel in "${SUBVOLS[@]}"; do
    snap_path="$SRC_MNT/${subvol_rel}_send"
    echo "[+] Отправляем вложенный сабволюм: ${subvol_rel}_send"
    sudo btrfs send "$snap_path" | sudo btrfs receive "$DEST_MNT"
done

# === Удаление временных снапшотов ===
if [ "$DELETE_SNAPS" = true ]; then
    echo "[+] Удаляем временные снапшоты"
    sudo btrfs subvolume delete "$SRC_MNT/${SRC_SUBVOL}_send"
    for subvol_rel in "${SUBVOLS[@]}"; do
        sudo btrfs subvolume delete "$SRC_MNT/${subvol_rel}_send"
    done
fi

echo "[✓] Перенос завершён."

