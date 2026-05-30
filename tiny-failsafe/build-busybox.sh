#!/bin/bash
# Compila o BusyBox estatico para aarch64 e popula o initramfs-root
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TINY_DIR="$ROOT/tiny-failsafe"
BUILD="$ROOT/build"
BUSYBOX_VER="1.36.1"
BUSYBOX_DIR="$BUILD/busybox-$BUSYBOX_VER"
INITRAMFS="$TINY_DIR/initramfs-root"

KVER="${KVER:-6.12.91}"

mkdir -p "$BUILD" "$TINY_DIR/out"

# 1. Baixar BusyBox
if [ ! -f "$BUILD/busybox-$BUSYBOX_VER.tar.bz2" ]; then
  echo ">> Baixando BusyBox $BUSYBOX_VER"
  curl -L --fail -o "$BUILD/busybox-$BUSYBOX_VER.tar.bz2" \
    "https://busybox.net/downloads/busybox-$BUSYBOX_VER.tar.bz2"
fi

# 2. Extrair
if [ ! -d "$BUSYBOX_DIR" ]; then
  echo ">> Extraindo BusyBox"
  tar -C "$BUILD" -xjf "$BUILD/busybox-$BUSYBOX_VER.tar.bz2"
fi

cd "$BUSYBOX_DIR"

# 3. Configurar estatico
if [ ! -f .config ]; then
  echo ">> Configurando BusyBox (allnoconfig + comandos essenciais)"
  make allnoconfig
  
  echo ">> Ajustando configuracoes de tamanho e basicas"
  CONFIG_TOOL="$ROOT/build/linux-$KVER/scripts/config"
  
  # Ativa o link estatico e ajustes de tamanho
  "$CONFIG_TOOL" --file .config --enable CONFIG_STATIC
  "$CONFIG_TOOL" --file .config --enable CONFIG_LFS
  "$CONFIG_TOOL" --file .config --enable CONFIG_SHOW_USAGE
  "$CONFIG_TOOL" --file .config --enable CONFIG_FEATURE_VERBOSE_USAGE
  
  # Ativa Shell ash
  "$CONFIG_TOOL" --file .config --enable CONFIG_ASH
  "$CONFIG_TOOL" --file .config --enable CONFIG_ASH_OPTIMIZE_FOR_SIZE
  "$CONFIG_TOOL" --file .config --enable CONFIG_ASH_INTERNAL_GLOB
  "$CONFIG_TOOL" --file .config --enable CONFIG_ASH_BASH_COMPAT
  "$CONFIG_TOOL" --file .config --enable CONFIG_ASH_JOB_CONTROL
  "$CONFIG_TOOL" --file .config --enable CONFIG_FEATURE_SH_MATH
  "$CONFIG_TOOL" --file .config --enable CONFIG_SH_IS_ASH
  
  # Ativa comandos essenciais de arquivos e sistema
  # (poweroff/reboot vem de CONFIG_HALT; setsid e exigido pelo /init que vira PID 1)
  for opt in CAT CHMOD CP DD DF DU ECHO ENV LN LS MKDIR MV RM SLEEP UNAME CLEAR PRINTF \
             DMESG FREE PS TOP KILL KILLALL VI LESS GREP EGREP FGREP FIND MKNOD MKFIFO HEAD TAIL HEXDUMP \
             MOUNT UMOUNT HALT SETSID \
             IFCONFIG ROUTE IP PING UDHCPC NC; do
    "$CONFIG_TOOL" --file .config --enable "CONFIG_$opt"
  done
  
  # Configura instalacao de symlinks
  "$CONFIG_TOOL" --file .config --enable CONFIG_INSTALL_APPLET_SYMLINKS
  
  echo ">> Resolvendo dependencias (yes \"\" | make oldconfig)"
  set +o pipefail
  yes "" | make oldconfig
  set -o pipefail
fi

# 4. Compilar e instalar
echo ">> Compilando BusyBox"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
make -j"$(nproc)" install

# 5. Popular initramfs-root
echo ">> Copiando arquivos para o initramfs-root: $INITRAMFS"
mkdir -p "$INITRAMFS"
rm -rf "$INITRAMFS"/* 2>/dev/null || true
cp -a _install/* "$INITRAMFS/"

# Criar diretorios virtuais e de montagem
mkdir -p "$INITRAMFS"/{dev,proc,sys,tmp,mnt,etc}

# 6. Criar o script /init
echo ">> Criando script /init"
cat > "$INITRAMFS/init" <<'EOF'
#!/bin/sh

# Monta os sistemas de arquivos virtuais essenciais
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev

# Exporta caminhos basicos
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export HOME=/root

# Inicia um shell interativo no Serial Console (/dev/ttyAML0) em background
if [ -c /dev/ttyAML0 ]; then
  /bin/busybox setsid /bin/sh -c 'exec /bin/sh </dev/ttyAML0 >/dev/ttyAML0 2>&1' &
fi

# Inicia o shell interativo principal na tela HDMI (/dev/tty1)
echo "=================================================="
echo "  Tanix TX9 (S912) Ultra-Fast Failsafe Shell      "
echo "=================================================="
echo "Running BusyBox on Linux kernel v$(uname -r)"
echo "Type 'help' for available commands."
echo "=================================================="

exec /bin/busybox setsid /bin/sh -c 'exec /bin/sh </dev/tty1 >/dev/tty1 2>&1'
EOF

chmod +x "$INITRAMFS/init"

echo ">> BusyBox pronto em $INITRAMFS"

