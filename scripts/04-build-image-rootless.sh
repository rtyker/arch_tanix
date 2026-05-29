#!/bin/bash
# Monta a imagem de SD (MBR: p1 FAT boot + p2 ext4 root) SEM root.
# Em vez de losetup/mount usa:
#   - fakeroot  : extrai o rootfs preservando dono root:root (uid/gid 0)
#   - mke2fs -d : popula a particao ext4 a partir de um diretorio
#   - mtools    : popula a particao FAT (mcopy/mmd) sem montar
# As particoes sao geradas como arquivos soltos e depois copiadas (dd) para
# dentro da imagem nos offsets corretos.
#   ./scripts/04-build-image-rootless.sh
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

for t in parted mke2fs mkfs.vfat mcopy mmd fakeroot; do
  command -v "$t" >/dev/null || { echo "FALTA $t"; exit 1; }
done
[ -f "$OUT/KERNEL" ]   || { echo "FALTA out/KERNEL (rode 02-package-kernel.sh)"; exit 1; }
[ -d "$OUT/modules" ]  || { echo "FALTA out/modules"; exit 1; }
[ -f "$ROOTFS_TAR" ]   || { echo "FALTA rootfs (rode 03-fetch-rootfs.sh)"; exit 1; }
[ -f "$ROOT/config/flavors/$FLAVOR.pkgs" ] || { echo "flavor invalido: '$FLAVOR' (veja config/flavors/)"; exit 1; }
echo ">> flavor: $FLAVOR"

WORK="$(mktemp -d)"
BOOTIMG="$WORK/boot.fat"
ROOTIMG="$WORK/root.ext4"
ROOTDIR="$WORK/rootdir"
ENVF="$WORK/fakeroot.env"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

ROOT_MB=$((IMG_SIZE_MB - BOOT_MB - 1))   # 1MiB de alinhamento inicial

echo ">> criando particao FAT (${BOOT_MB}MB) e populando"
truncate -s "${BOOT_MB}M" "$BOOTIMG"
mkfs.vfat -n TX9BOOT "$BOOTIMG" >/dev/null
export MTOOLS_SKIP_CHECK=1
mcopy -i "$BOOTIMG" "$OUT/KERNEL" ::KERNEL
mcopy -i "$BOOTIMG" "$BOOT/boot.scr" "$BOOT/aml_autoscript" \
      "$BOOT/s905_autoscript" "$BOOT/emmc_autoscript" ::
mmd   -i "$BOOTIMG" ::dtb
mcopy -i "$BOOTIMG" "$BOOT/amlogic/$DTB" "::dtb/$DTB"

# uEnv.ini (root sera referenciado por LABEL=TX9ROOT — UUID so existira apos mke2fs)
cat > "$WORK/uEnv.ini" <<EOF
dtb_name=/dtb/$DTB
bootargs=root=LABEL=TX9ROOT rootfstype=ext4 rootwait rw console=ttyAML0,115200n8 console=tty0
EOF
mcopy -i "$BOOTIMG" "$WORK/uEnv.ini" ::uEnv.ini

echo ">> montando arvore do rootfs sob fakeroot"
# Todo o trabalho que precisa de dono root:root roda dentro de um unico
# contexto fakeroot, persistido em $ENVF, terminando no mke2fs -d.
fakeroot -s "$ENVF" -- bash -euo pipefail -c '
  ROOTDIR="$1"; ROOTFS_TAR="$2"; OUT="$3"; REPO="$4"; FLAVOR="$5"
  mkdir -p "$ROOTDIR"
  echo "   extraindo rootfs ArchLinuxARM"
  tar -xpf "$ROOTFS_TAR" -C "$ROOTDIR"
  echo "   instalando modulos do kernel (descartando os do kernel de fabrica)"
  rm -rf "$ROOTDIR"/usr/lib/modules/* 2>/dev/null || true
  mkdir -p "$ROOTDIR/usr/lib/modules"
  cp -a "$OUT/modules/lib/modules/." "$ROOTDIR/usr/lib/modules/"
  echo "   fstab (root por LABEL)"
  cat > "$ROOTDIR/etc/fstab" <<FSTAB
# <file system>   <dir>   <type>  <options>          <dump> <pass>
LABEL=TX9ROOT     /       ext4    defaults,noatime   0      1
FSTAB
  "$REPO/scripts/lib/apply-flavor.sh" "$ROOTDIR" "$FLAVOR" "$REPO"
' _ "$ROOTDIR" "$ROOTFS_TAR" "$OUT" "$ROOT" "$FLAVOR"

echo ">> gerando particao ext4 (${ROOT_MB}MB) a partir do diretorio"
# Reaproveita o mesmo estado fakeroot para que mke2fs leia dono root:root.
fakeroot -i "$ENVF" -- \
  mke2fs -q -t ext4 -L TX9ROOT -d "$ROOTDIR" "$ROOTIMG" "${ROOT_MB}M"

echo ">> montando imagem final $IMG (${IMG_SIZE_MB}MB)"
rm -f "$IMG"
truncate -s "${IMG_SIZE_MB}M" "$IMG"
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 1MiB "$((BOOT_MB + 1))MiB"
parted -s "$IMG" mkpart primary ext4  "$((BOOT_MB + 1))MiB" 100%
parted -s "$IMG" set 1 boot on

# Copia as particoes para dentro da imagem nos offsets (1MiB e BOOT_MB+1 MiB).
dd if="$BOOTIMG" of="$IMG" bs=1M seek=1 conv=notrunc status=none
dd if="$ROOTIMG" of="$IMG" bs=1M seek="$((BOOT_MB + 1))" conv=notrunc status=none

sync
echo ">> imagem pronta: $IMG"
ls -la "$IMG"
