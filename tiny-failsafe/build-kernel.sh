#!/bin/bash
# Compila o kernel e copia para tiny-failsafe/out/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KVER="${KVER:-6.12.91}"
SRC="$ROOT/build/linux-$KVER"
TINY_DIR="$ROOT/tiny-failsafe"
OUT="$TINY_DIR/out"

if [ ! -d "$SRC" ]; then
  echo "FALTA fonte do kernel em $SRC."
  exit 1
fi

cd "$SRC"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
JOBS="$(nproc)"

echo ">> Compilando Image (-j$JOBS)"
make -j"$JOBS" Image dtbs

echo ">> Coletando artefatos em $OUT"
mkdir -p "$OUT"
cp -v arch/arm64/boot/Image "$OUT/Image"
mkdir -p "$OUT/dtb"
cp -v arch/arm64/boot/dts/amlogic/meson-gxm-*.dtb "$OUT/dtb/" 2>/dev/null || true

echo ">> KERNEL BUILD OK: $(ls -la "$OUT/Image")"
