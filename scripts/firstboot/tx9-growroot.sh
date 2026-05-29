#!/bin/bash
# tx9-growroot.sh — no 1o boot, cresce a particao do root e o ext4 para ocupar
# TODO o espaco livre do device (cartao/pendrive maior que a imagem de 4 GiB).
# Roda uma vez (oneshot), ANTES do tx9-firstboot (assim o pacman ja escreve num
# root grande). Usa so ferramentas do tarball base: sfdisk + partx (util-linux)
# e resize2fs (e2fsprogs) — sem growpart/parted.
set -uo pipefail

STAMP=/var/lib/tx9-growroot.done
LOG=/var/log/tx9-growroot.log
[ -f "$STAMP" ] && exit 0
exec >>"$LOG" 2>&1
echo "===== tx9-growroot $(date -u) ====="

ROOTSRC="$(findmnt -no SOURCE /)"                       # ex: /dev/sda2
BASE="$(basename "$ROOTSRC")"                           # sda2
DISK="/dev/$(lsblk -no PKNAME "$ROOTSRC" 2>/dev/null | head -1)"   # /dev/sda
PARTNUM="$(cat "/sys/class/block/$BASE/partition" 2>/dev/null)"    # 2

if [ ! -b "$DISK" ] || [ -z "$PARTNUM" ]; then
  echo "!! nao identifiquei disco/particao do root (src=$ROOTSRC disk=$DISK part=$PARTNUM) — pulando"
  touch "$STAMP"; exit 0
fi
echo ">> root=$ROOTSRC disk=$DISK part=$PARTNUM"
echo ">> antes:"; df -h / | tail -1

# 1) estende a particao ate o fim do disco. Campos: start vazio (mantem) + '+'
#    (usa todo o espaco livre). --no-tell-kernel pq a particao esta montada;
#    quem avisa o kernel e o partx logo abaixo (via BLKPG, funciona montado).
if echo ', +' | sfdisk --no-reread --no-tell-kernel -N "$PARTNUM" "$DISK"; then
  partx -u "$DISK" 2>/dev/null || true                 # atualiza tamanho no kernel
  echo ">> particao estendida; resize2fs online"
  resize2fs "$ROOTSRC" || { echo "!! resize2fs falhou"; exit 1; }
else
  echo "!! sfdisk nao estendeu (sem espaco livre?) — seguindo"
fi

touch "$STAMP"
echo ">> depois:"; df -h / | tail -1
echo "===== fim ====="
