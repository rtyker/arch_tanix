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
# DTB do NOSSO kernel (out/dtb/), nunca o do LibreELEC: tem que casar com o kernel.
DTB="${DTB:-meson-gxm-s912-libretech-pc.dtb}"
FLAVOR="${FLAVOR:-minimal}"             # minimal | video | lxqt | rootfs-failsafe (config/flavors/)
IMG_SIZE_MB="${IMG_SIZE_MB:-4096}"
BOOT_MB=256
ROOTFS_TAR="$BUILD/ArchLinuxARM-aarch64-latest.tar.gz"
# PREINSTALL=1: instala os pacotes do flavor JA no build (qemu-aarch64 + chroot),
# em vez de no 1o boot. Boot fica rapido e dispensa Ethernet no 1o boot.
PREINSTALL="${PREINSTALL:-1}"
NOFIRSTBOOT=0; [ -f "$ROOT/config/flavors/$FLAVOR.nofirstboot" ] && NOFIRSTBOOT=1

[ "$(id -u)" -eq 0 ] || { echo "rode como root (sudo)"; exit 1; }
[ -f "$OUT/KERNEL" ]   || { echo "FALTA out/KERNEL (rode 02-package-kernel.sh)"; exit 1; }
[ -d "$OUT/modules" ]  || { echo "FALTA out/modules"; exit 1; }
[ -f "$OUT/dtb/$DTB" ] || { echo "FALTA $OUT/dtb/$DTB (dtb do nosso kernel; rode 01-build-kernel.sh)"; exit 1; }
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

# disk-id fixo no MBR -> PARTUUID deterministico (root=PARTUUID resolve sem initramfs)
DISKID=0x54583900                          # ASCII "TX9\0"
PARTUUID="${DISKID#0x}-02"                  # p2 = rootfs ext4 -> 54583900-02
sfdisk --disk-id "$IMG" "$DISKID" >/dev/null
echo ">> disk-id MBR = $DISKID  (PARTUUID root = $PARTUUID)"

LO="$(losetup -f --show -P "$IMG")"
echo ">> loop: $LO"
mkfs.vfat -n TX9BOOT "${LO}p1"
mkfs.ext4 -F -L TX9ROOT "${LO}p2"

ROOTUUID="$(blkid -s UUID -o value "${LO}p2")"
echo ">> root UUID: $ROOTUUID"

MNT="$(mktemp -d)"
mount "${LO}p2" "$MNT"

echo ">> extraindo rootfs ArchLinuxARM"
tar -xpf "$ROOTFS_TAR" -C "$MNT"

# Descarta o /boot generico do tarball (kernel/initramfs/dtbs do ArchLinuxARM —
# usamos os NOSSOS). Tambem evita ENOSPC: esse /boot tem ~350MB (initramfs+dtbs)
# e nao caberia na FAT de ${BOOT_MB}MB se ela ja estivesse montada aqui.
echo ">> descartando /boot generico do tarball"
rm -rf "$MNT"/boot/*

# So agora monta a particao FAT de boot (vazia) para receber o nosso KERNEL.
mkdir -p "$MNT/boot"
mount "${LO}p1" "$MNT/boot"

echo ">> instalando modulos do kernel (descartando os do kernel de fabrica)"
rm -rf "$MNT"/usr/lib/modules/* 2>/dev/null || true
mkdir -p "$MNT/usr/lib/modules"
cp -a "$OUT/modules/lib/modules/." "$MNT/usr/lib/modules/"

echo ">> populando boot (FAT)"
cp "$OUT/KERNEL" "$MNT/boot/KERNEL"
cp "$BOOT/boot.scr" "$BOOT/aml_autoscript" "$BOOT/s905_autoscript" "$BOOT/emmc_autoscript" "$MNT/boot/"
mkdir -p "$MNT/boot/dtb"
cp "$OUT/dtb/$DTB" "$MNT/boot/dtb/$DTB"

echo ">> uEnv.ini"
# bootargs base + extras opcionais do flavor (config/flavors/<flavor>.bootargs).
BOOTARGS="root=PARTUUID=$PARTUUID rootfstype=ext4 rootwait rw console=ttyAML0,115200n8 console=tty0"
if [ -f "$ROOT/config/flavors/$FLAVOR.bootargs" ]; then
  EXTRA="$(awk 'NF && $1 !~ /^#/ {print $1}' "$ROOT/config/flavors/$FLAVOR.bootargs" | paste -sd' ')"
  [ -n "$EXTRA" ] && BOOTARGS="$BOOTARGS $EXTRA" && echo ">> bootargs extra ($FLAVOR): $EXTRA"
fi
cat > "$MNT/boot/uEnv.ini" <<EOF
dtb_name=/dtb/$DTB
bootargs=$BOOTARGS
EOF

echo ">> fstab"
cat > "$MNT/etc/fstab" <<EOF
# <file system>   <dir>   <type>  <options>          <dump> <pass>
UUID=$ROOTUUID    /       ext4    defaults,noatime   0      1
EOF

echo ">> aplicando flavor"
"$ROOT/scripts/lib/apply-flavor.sh" "$MNT" "$FLAVOR" "$ROOT"

# ---------------------------------------------------------------------------
# Pre-instalacao dos pacotes do flavor no proprio rootfs (qemu-aarch64 + chroot),
# em vez de deixar para o tx9-firstboot no 1o boot. Cria o stamp do firstboot
# para ele NAO repetir no boot real -> boot rapido e sem rede obrigatoria.
# ---------------------------------------------------------------------------
if [ "$NOFIRSTBOOT" != 1 ] && [ "$PREINSTALL" = 1 ]; then
  echo ">> pre-instalando pacotes do flavor (qemu-aarch64 + chroot)"
  command -v qemu-aarch64-static >/dev/null || { echo "FALTA qemu-aarch64-static (pacman -S qemu-user-static)"; exit 1; }
  command -v arch-chroot       >/dev/null || { echo "FALTA arch-chroot (pacman -S arch-install-scripts)"; exit 1; }

  # binfmt do aarch64 com flag F (fix binary: funciona dentro do chroot)
  if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
    echo "   registrando binfmt qemu-aarch64 (flag F)"
    printf '%s\n' ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F' \
      > /proc/sys/fs/binfmt_misc/register
  fi

  # DNS dentro do chroot (substitui temporariamente o symlink do resolved)
  rm -f "$MNT/etc/resolv.conf"; cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"

  arch-chroot "$MNT" /bin/bash -euo pipefail <<'CHROOT'
echo ">>> [chroot] pacman-key --init/--populate"
pacman-key --init
pacman-key --populate archlinuxarm
mapfile -t PKGS < <(awk 'NF && $1 !~ /^#/ {print $1}' /etc/tx9/flavor.pkgs)
echo ">>> [chroot] instalando ${#PKGS[@]} pacotes: ${PKGS[*]}"
pacman -Syu --noconfirm --needed "${PKGS[@]}"
echo ">>> [chroot] locale-gen"
locale-gen
echo ">>> [chroot] habilitando unidades do flavor"
if [ -f /etc/tx9/flavor.enable ]; then
  while read -r u _; do
    [ -z "$u" ] && continue; case "$u" in \#*) continue ;; esac
    systemctl enable "$u" || true
  done < /etc/tx9/flavor.enable
fi
if [ -f /etc/tx9/flavor.target ]; then
  t="$(head -n1 /etc/tx9/flavor.target)"; [ -n "$t" ] && systemctl set-default "$t" || true
fi
echo ">>> [chroot] marcando firstboot como concluido + limpando cache"
install -d /var/lib; : > /var/lib/tx9-firstboot.done
systemctl disable tx9-firstboot.service 2>/dev/null || true
yes | pacman -Scc >/dev/null 2>&1 || true
echo ">>> [chroot] fim"
CHROOT

  # restaura o resolv.conf gerenciado pelo systemd-resolved
  rm -f "$MNT/etc/resolv.conf"; ln -sf /run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"
  echo ">> pre-instalacao concluida (pacotes ja na imagem; firstboot nao roda no boot)"
else
  echo ">> sem pre-instalacao (PREINSTALL=$PREINSTALL, nofirstboot=$NOFIRSTBOOT) — pacotes pelo tx9-firstboot no 1o boot"
fi

sync
echo ">> imagem pronta: $IMG"
