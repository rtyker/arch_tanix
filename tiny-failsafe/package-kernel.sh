#!/bin/bash
# Empacota o Image cru do tiny-failsafe como uImage legacy (LZO)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TINY_DIR="$ROOT/tiny-failsafe"
OUT="$TINY_DIR/out"
LOAD=0x02000000

command -v mkimage >/dev/null || { echo "FALTA mkimage (pacote uboot-tools)"; exit 1; }
command -v lzop   >/dev/null || { echo "FALTA lzop"; exit 1; }
[ -f "$OUT/Image" ] || { echo "FALTA $OUT/Image (rode build-kernel.sh)"; exit 1; }

echo ">> Comprimindo Image (lzo)"
lzop -9 -f -o "$OUT/Image.lzo" "$OUT/Image"

echo ">> Gerando uImage (KERNEL)"
mkimage -A arm64 -O linux -T kernel -C lzo \
  -a "$LOAD" -e "$LOAD" -n "Linux-TX9-Tiny" \
  -d "$OUT/Image.lzo" "$OUT/KERNEL"

echo ">> OK: $(ls -la "$OUT/KERNEL")"
