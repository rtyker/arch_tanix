#!/bin/bash
# Empacota o Image cru do ram-failsafe como uImage legacy
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAM_DIR="$ROOT/ram-failsafe"
OUT="$RAM_DIR/out"
LOAD=0x03000000

command -v mkimage >/dev/null || { echo "FALTA mkimage (pacote uboot-tools)"; exit 1; }
command -v lzop   >/dev/null || { echo "FALTA lzop"; exit 1; }
[ -f "$OUT/Image" ] || { echo "FALTA $OUT/Image (rode build-kernel.sh)"; exit 1; }

# Nós desativamos a compressão LZO para contornar o erro 'LZO: uncompress or overwrite error -6'
# que ocorre no U-Boot de fábrica com kernels monolíticos.
echo ">> Gerando uImage sem compressão (KERNEL)"
mkimage -A arm64 -O linux -T kernel -C none \
  -a "$LOAD" -e "$LOAD" -n "Linux-TX9-RAM" \
  -d "$OUT/Image" "$OUT/KERNEL"

echo ">> OK: $(ls -la "$OUT/KERNEL")"
