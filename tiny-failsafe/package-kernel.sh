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

# Valida se o tamanho comprimido vai causar sobreposição de memória no U-Boot.
# O container do KERNEL é carregado em 0x01080000. Se a descompressão (LOAD=0x02000000)
# iniciar antes do fim do container carregado, haverá corrupção da stream LZO (error -6/-8).
# Limite máximo de tamanho comprimido = 0x02000000 - 0x01080000 - 64 (header) = 16252864 bytes (~15.5MB)
SZ=$(stat -c%s "$OUT/Image.lzo")
MAX_SZ=16252864
if [ "$LOAD" = "0x02000000" ] && [ "$SZ" -gt "$MAX_SZ" ]; then
  echo "⚠️  AVISO DE RISCO DE BOOTLOOP:"
  echo "    O kernel comprimido ($((SZ/1024/1024))MB) excedeu o limite seguro de 15.5MB!"
  echo "    Carregando em 0x01080000 e descomprimindo para LOAD=0x02000000 haverá SOBREPOSIÇÃO."
  echo "    Isso causará 'LZO: uncompress or overwrite error' e bootloop."
  echo "    Certifique-se de rodar ./tiny-failsafe/prune-config.sh antes de compilar para reduzir o kernel,"
  echo "    ou mude o LOAD para 0x03000000 em tiny-failsafe/package-kernel.sh."
  echo "----------------------------------------------------------------------------------"
fi

echo ">> Gerando uImage (KERNEL)"
mkimage -A arm64 -O linux -T kernel -C lzo \
  -a "$LOAD" -e "$LOAD" -n "Linux-TX9-Tiny" \
  -d "$OUT/Image.lzo" "$OUT/KERNEL"

echo ">> OK: $(ls -la "$OUT/KERNEL")"
