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
# DTB do NOSSO kernel (out/dtb/), nunca o do LibreELEC: tem que casar com o kernel.
# meson-gxm-s912-libretech-pc e o modelo que o box aceita (o proprio LibreELEC
# boota com ele). NAO usar tx9-pro: nao existe no kernel mainline 6.12.
DTB="${DTB:-meson-gxm-s912-libretech-pc.dtb}"
FLAVOR="${FLAVOR:-minimal}"             # minimal | video | lxqt | rootfs-failsafe (config/flavors/)
IMG_SIZE_MB="${IMG_SIZE_MB:-4096}"
BOOT_MB=256
ROOTFS_TAR="$BUILD/ArchLinuxARM-aarch64-latest.tar.gz"

for t in parted sfdisk mke2fs mkfs.vfat mcopy mmd fakeroot; do
  command -v "$t" >/dev/null || { echo "FALTA $t"; exit 1; }
done
[ -f "$OUT/KERNEL" ]   || { echo "FALTA out/KERNEL (rode 02-package-kernel.sh)"; exit 1; }
[ -d "$OUT/modules" ]  || { echo "FALTA out/modules"; exit 1; }
[ -f "$OUT/dtb/$DTB" ] || { echo "FALTA $OUT/dtb/$DTB (dtb do nosso kernel; rode 01-build-kernel.sh)"; exit 1; }
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
mcopy -i "$BOOTIMG" "$OUT/dtb/$DTB" "::dtb/$DTB"

# bootargs base + extras opcionais do flavor (config/flavors/<flavor>.bootargs).
# O rootfs-failsafe usa isso para ligar earlycon/initcall_debug/ignore_loglevel etc.
# root por PARTUUID (MBR): o kernel resolve nativamente, SEM initramfs e SEM
# depender da ordem de enumeracao (sda/sdb). Para MBR o PARTUUID e
# "<disk-id 8 hex>-<NN da particao>". Fixamos o disk-id (DISKID) no MBR via
# 'sfdisk --disk-id' mais abaixo, entao o PARTUUID da p2 (ext4) e deterministico.
# 'rootwait' aguarda o dispositivo (USB enumera tarde).
DISKID=0x54583900                          # ASCII "TX9\0" — so pra ser reconhecivel
PARTUUID="${DISKID#0x}-02"                  # p2 = rootfs ext4  -> 54583900-02
BOOTARGS="root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait rw console=ttyAML0,115200n8 console=tty0"
if [ -f "$ROOT/config/flavors/$FLAVOR.bootargs" ]; then
  EXTRA="$(awk 'NF && $1 !~ /^#/ {print $1}' "$ROOT/config/flavors/$FLAVOR.bootargs" | paste -sd' ')"
  [ -n "$EXTRA" ] && BOOTARGS="$BOOTARGS $EXTRA" && echo ">> bootargs extra ($FLAVOR): $EXTRA"
fi

# uEnv.ini (root sera referenciado por LABEL=TX9ROOT — UUID so existira apos mke2fs)
cat > "$WORK/uEnv.ini" <<EOF
dtb_name=/dtb/$DTB
bootargs=$BOOTARGS
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

# disk-id fixo no MBR -> PARTUUID deterministico (casado com root=PARTUUID acima).
# (so altera 4 bytes em 0x1b8; nao mexe nas particoes copiadas a seguir)
sfdisk --disk-id "$IMG" "$DISKID" >/dev/null
echo ">> disk-id MBR = $DISKID  (PARTUUID root = $PARTUUID)"

# Copia as particoes para dentro da imagem nos offsets (1MiB e BOOT_MB+1 MiB).
dd if="$BOOTIMG" of="$IMG" bs=1M seek=1 conv=notrunc status=none
dd if="$ROOTIMG" of="$IMG" bs=1M seek="$((BOOT_MB + 1))" conv=notrunc status=none

sync
echo ">> imagem pronta: $IMG"
ls -la "$IMG"
