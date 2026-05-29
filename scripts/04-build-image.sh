#!/bin/bash
# Monta a imagem de SD (MBR: p1 FAT boot + p2 ext4 root) inspirada no esquema
# Amlogic-ng do LibreELEC. Requer root (losetup/mount).
#   sudo ./scripts/04-build-image.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
BOOT="$ROOT/boot"
BUILD="$ROOT/build"
IMG="$OUT/arch-tx9.img"
DTB="${DTB:-meson-gxm-tx9-pro.dtb}"     # ou meson-gxm-s912-libretech-pc.dtb
FLAVOR="${FLAVOR:-minimal}"             # minimal | video | lxqt (config/flavors/)
IMG_SIZE_MB="${IMG_SIZE_MB:-4096}"
BOOT_MB=256
ROOTFS_TAR="$BUILD/ArchLinuxARM-aarch64-latest.tar.gz"

[ "$(id -u)" -eq 0 ] || { echo "rode como root (sudo)"; exit 1; }
[ -f "$OUT/KERNEL" ]   || { echo "FALTA out/KERNEL (rode 02-package-kernel.sh)"; exit 1; }
[ -d "$OUT/modules" ]  || { echo "FALTA out/modules"; exit 1; }
[ -f "$ROOTFS_TAR" ]   || { echo "FALTA rootfs (rode 03-fetch-rootfs.sh)"; exit 1; }
[ -f "$ROOT/config/flavors/$FLAVOR.pkgs" ] || { echo "flavor invalido: '$FLAVOR' (veja config/flavors/)"; exit 1; }
echo ">> flavor: $FLAVOR"

cleanup() { set +e; [ -n "${MNT:-}" ] && umount -R "$MNT" 2>/dev/null; [ -n "${LO:-}" ] && losetup -d "$LO" 2>/dev/null; [ -n "${MNT:-}" ] && rmdir "$MNT" 2>/dev/null; }
trap cleanup EXIT

echo ">> criando imagem $IMG (${IMG_SIZE_MB}MB)"
rm -f "$IMG"
truncate -s "${IMG_SIZE_MB}M" "$IMG"

echo ">> particionando (MBR: FAT + ext4)"
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB "$((BOOT_MB + 1))MiB"
parted -s "$IMG" mkpart primary ext4  "$((BOOT_MB + 1))MiB" 100%
parted -s "$IMG" set 1 boot on

LO="$(losetup -f --show -P "$IMG")"
echo ">> loop: $LO"
mkfs.vfat -n TX9BOOT "${LO}p1"
mkfs.ext4 -F -L TX9ROOT "${LO}p2"

ROOTUUID="$(blkid -s UUID -o value "${LO}p2")"
echo ">> root UUID: $ROOTUUID"

MNT="$(mktemp -d)"
mount "${LO}p2" "$MNT"
mkdir -p "$MNT/boot"
mount "${LO}p1" "$MNT/boot"

echo ">> extraindo rootfs ArchLinuxARM"
tar -xpf "$ROOTFS_TAR" -C "$MNT"

echo ">> instalando modulos do kernel (descartando os do kernel de fabrica)"
rm -rf "$MNT"/usr/lib/modules/* 2>/dev/null || true
mkdir -p "$MNT/usr/lib/modules"
cp -a "$OUT/modules/lib/modules/." "$MNT/usr/lib/modules/"

echo ">> populando boot (FAT)"
cp "$OUT/KERNEL" "$MNT/boot/KERNEL"
cp "$BOOT/boot.scr" "$BOOT/aml_autoscript" "$BOOT/s905_autoscript" "$BOOT/emmc_autoscript" "$MNT/boot/"
mkdir -p "$MNT/boot/dtb"
cp "$BOOT/amlogic/$DTB" "$MNT/boot/dtb/$DTB"

echo ">> uEnv.ini"
cat > "$MNT/boot/uEnv.ini" <<EOF
dtb_name=/dtb/$DTB
bootargs=root=UUID=$ROOTUUID rootfstype=ext4 rootwait rw console=ttyAML0,115200n8 console=tty0
EOF

echo ">> fstab"
cat > "$MNT/etc/fstab" <<EOF
# <file system>   <dir>   <type>  <options>          <dump> <pass>
UUID=$ROOTUUID    /       ext4    defaults,noatime   0      1
EOF

echo ">> aplicando flavor"
"$ROOT/scripts/lib/apply-flavor.sh" "$MNT" "$FLAVOR" "$ROOT"

sync
echo ">> imagem pronta: $IMG"
