#!/bin/bash
# Gera a imagem bootavel de particao unica (FAT32) para o failsafe BusyBox
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAM_DIR="$ROOT/ram-failsafe"
OUT="$RAM_DIR/out"
BOOT="$ROOT/boot"
IMG="$OUT/ram-failsafe.img"
DTB="${DTB:-meson-gxm-s912-libretech-pc.dtb}"

# Verifica dependencias
for t in parted mkfs.vfat mcopy mmd; do
  command -v "$t" >/dev/null || { echo "FALTA $t"; exit 1; }
done

[ -f "$OUT/KERNEL" ]   || { echo "FALTA $OUT/KERNEL (rode package-kernel.sh)"; exit 1; }
[ -f "$OUT/dtb/$DTB" ] || { echo "FALTA $OUT/dtb/$DTB (rode build-kernel.sh)"; exit 1; }

WORK="$(mktemp -d)"
BOOTIMG="$WORK/boot.fat"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Particao de 32MB
BOOT_MB=32
# Imagem de 33MB (1MB de offset inicial + 32MB de particao)
IMG_SIZE_MB=$((BOOT_MB + 1))

echo ">> Criando particao FAT (${BOOT_MB}MB) e populando..."
truncate -s "${BOOT_MB}M" "$BOOTIMG"
mkfs.vfat -n TX9RAM "$BOOTIMG" >/dev/null

export MTOOLS_SKIP_CHECK=1
mcopy -i "$BOOTIMG" "$OUT/KERNEL" ::KERNEL
mcopy -i "$BOOTIMG" "$BOOT/boot.scr" "$BOOT/aml_autoscript" \
      "$BOOT/s905_autoscript" "$BOOT/emmc_autoscript" ::
mmd   -i "$BOOTIMG" ::dtb
mcopy -i "$BOOTIMG" "$OUT/dtb/$DTB" "::dtb/$DTB"

# Grava uEnv.ini com os bootargs do Kernel para initramfs + HDMI console
echo ">> Escrevendo uEnv.ini..."
BOOTARGS="console=ttyAML0,115200n8 console=tty1 earlycon=meson,0xc81004c0 rdinit=/init ignore_loglevel"

cat > "$WORK/uEnv.ini" <<EOF
dtb_name=/dtb/$DTB
bootargs=$BOOTARGS
EOF
mcopy -i "$BOOTIMG" "$WORK/uEnv.ini" ::uEnv.ini

echo ">> Criando imagem final $IMG (${IMG_SIZE_MB}MB)"
rm -f "$IMG"
truncate -s "${IMG_SIZE_MB}M" "$IMG"

echo ">> Particionando..."
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB 100%
parted -s "$IMG" set 1 boot on

echo ">> Gravando particao FAT para a imagem..."
dd if="$BOOTIMG" of="$IMG" bs=1M seek=1 conv=notrunc status=none

sync
echo ">> Imagem pronta: $IMG"
echo ">> Para gravar no cartao SD/USB, execute:"
echo "   sudo dd if=$IMG of=/dev/sdX bs=4M conv=fsync status=progress"
