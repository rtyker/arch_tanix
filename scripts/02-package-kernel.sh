#!/bin/bash
# Empacota o Image cru como uImage legacy (LZO), igual ao LibreELEC no S912.
# Header de referencia lido do box: arch=arm64 os=linux type=kernel comp=lzo
#   load=0x01d80000 entry=0x01d80000
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
LOAD=0x01d80000

command -v mkimage >/dev/null || { echo "FALTA mkimage (pacote uboot-tools)"; exit 1; }
command -v lzop   >/dev/null || { echo "FALTA lzop"; exit 1; }
[ -f "$OUT/Image" ] || { echo "FALTA $OUT/Image (rode 01-build-kernel.sh)"; exit 1; }

echo ">> comprimindo Image (lzo)"
lzop -9 -f -o "$OUT/Image.lzo" "$OUT/Image"

echo ">> gerando uImage (KERNEL)"
mkimage -A arm64 -O linux -T kernel -C lzo \
  -a "$LOAD" -e "$LOAD" -n "Linux-TX9" \
  -d "$OUT/Image.lzo" "$OUT/KERNEL"

echo ">> OK: $(ls -la "$OUT/KERNEL")"
