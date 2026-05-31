#!/bin/bash
# Compila o kernel e copia para ram-failsafe/out/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KVER="${KVER:-6.12.91}"
SRC="$ROOT/build/linux-$KVER"
OBJ="$ROOT/build/obj-ram"        # mesmo dir out-of-tree gerado por prune-config.sh
RAM_DIR="$ROOT/ram-failsafe"
OUT="$RAM_DIR/out"

if [ ! -d "$SRC" ]; then
  echo "FALTA fonte do kernel em $SRC."
  exit 1
fi
if [ ! -f "$OBJ/.config" ]; then
  echo "FALTA $OBJ/.config — rode ./ram-failsafe/prune-config.sh antes."
  exit 1
fi

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
JOBS="$(nproc)"

# Compila out-of-tree em obj-ram (igual ao 01-build-kernel.sh, que usa obj-rootfs):
# mantem o kernel enxuto do failsafe isolado do kernel do rootfs real.
echo ">> Compilando Image (-j$JOBS) em $OBJ"
make -C "$SRC" O="$OBJ" -j"$JOBS" Image dtbs

echo ">> Coletando artefatos em $OUT"
mkdir -p "$OUT"
cp -v "$OBJ/arch/arm64/boot/Image" "$OUT/Image"
mkdir -p "$OUT/dtb"
cp -v "$OBJ"/arch/arm64/boot/dts/amlogic/meson-gxm-*.dtb "$OUT/dtb/" 2>/dev/null || true

echo ">> KERNEL BUILD OK: $(ls -la "$OUT/Image")"
