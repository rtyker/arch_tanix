#!/bin/bash
# Empacota o Image cru como uImage legacy (LZO).
#
# ATENCAO ao endereco de load/entry (-a/-e): e o destino para onde o bootm
# DESCOMPRIME o Image. O U-Boot de fabrica carrega o container do uImage em
# ${loadaddr} (padrao Amlogic ~0x1080000) e descomprime para este endereco.
#
# Duas restricoes simultaneas:
#  1) o destino NAO pode invadir o container (senao a descompressao sobrescreve
#     bytes lzo ainda nao lidos -> stream corrompe -> kernel nunca inicia);
#  2) o destino tem que estar numa faixa de RAM que o U-Boot de fabrica alcanca
#     (bootm com janela limitada): enderecos altos (testamos 0x08000000=128MB)
#     travam congelado na bootlogo, sem nunca executar o kernel.
#
# Solucao: descomprimir LOGO ACIMA do nosso container, num endereco baixo.
#   container = loadaddr(~0x1080000) + tamanho do KERNEL(~15.7MB) ~= 0x1F80000 (~31.5MB)
#   LOAD=0x02000000 (32MB) fica logo acima do container E na MESMA faixa de RAM
#   (~32-70MB) que o LibreELEC comprovadamente usa (ele descomprime em 0x01d80000
#   ~30.5MB). O Image arm64 e relocavel (flag "2MB anywhere", header offset 0x18).
# OBS: se um dia o KERNEL crescer e o container passar de 0x02000000, subir o LOAD
#   (sempre 2MB-aligned) para logo acima do novo fim do container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
LOAD=0x02000000

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
