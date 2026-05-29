#!/bin/bash
# Build mainline aarch64 kernel para Tanix TX9 (Amlogic S912 / meson-gxm)
set -euo pipefail

KVER="${KVER:-6.12.91}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
OUT="$ROOT/out"
SRC="$BUILD/linux-$KVER"
JOBS="$(nproc)"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

mkdir -p "$BUILD" "$OUT"

# 1. baixar fonte
if [ ! -f "$BUILD/linux-$KVER.tar.xz" ]; then
  echo ">> baixando linux-$KVER"
  curl -L --fail -o "$BUILD/linux-$KVER.tar.xz" \
    "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
fi

# 2. extrair
if [ ! -d "$SRC" ]; then
  echo ">> extraindo"
  tar -C "$BUILD" -xf "$BUILD/linux-$KVER.tar.xz"
fi

cd "$SRC"

# 3. config: defconfig arm64 (cobre meson-gxm, panfrost, etc.)
if [ ! -f .config ]; then
  echo ">> defconfig"
  make defconfig
fi

# 4. compilar Image + dtbs + modulos
echo ">> build Image (-j$JOBS)"
make -j"$JOBS" Image dtbs
echo ">> build modules"
make -j"$JOBS" modules

# 5. coletar artefatos
echo ">> coletando artefatos em $OUT"
cp -v arch/arm64/boot/Image "$OUT/"
mkdir -p "$OUT/dtb"
cp -v arch/arm64/boot/dts/amlogic/meson-gxm-*.dtb "$OUT/dtb/" 2>/dev/null || true

# instalar modulos em staging
rm -rf "$OUT/modules"
make INSTALL_MOD_PATH="$OUT/modules" modules_install

echo ">> KERNEL BUILD OK: $(ls -la "$OUT/Image")"
