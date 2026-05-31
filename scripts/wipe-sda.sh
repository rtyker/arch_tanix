#!/bin/bash
# wipe-sda.sh — destroi FORCADAMENTE a tabela de particoes e assinaturas de um
# dispositivo USB (padrao /dev/sda), deixando-o limpo para um "dd" manual.
#
# Resolve o classico "Device or resource busy / re-reading partition table
# failed": desmonta tudo, tira swap, mata quem segura o device, apaga MBR/GPT
# (inicio e fim) e forca o kernel a reler a tabela.
#
# Uso:
#   sudo ./scripts/wipe-sda.sh [/dev/sdX]     # pergunta confirmacao
#   sudo FORCE=1 ./scripts/wipe-sda.sh /dev/sdX  # sem perguntar
#
# Depois: grave a imagem manualmente, ex.:
#   sudo dd if=out/arch-tx9-busybox-video-x11.img of=/dev/sdX bs=4M conv=fsync status=progress
#   sync
set -euo pipefail

DEV="${1:-/dev/sda}"
FORCE="${FORCE:-0}"

die() { echo "ERRO: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "rode como root (sudo)."
[ -b "$DEV" ] || die "'$DEV' nao e um dispositivo de bloco."

# Normaliza para o disco-base (ex.: /dev/sda2 -> /dev/sda) e nome curto (sda).
BASE="/dev/$(lsblk -ndo PKNAME "$DEV" 2>/dev/null || true)"
[ "$BASE" = "/dev/" ] && BASE="$DEV"      # ja era o disco
NAME="$(basename "$BASE")"

# ---- GUARDAS DE SEGURANCA ---------------------------------------------------
# 1. Recusa NVMe/MMC (provaveis discos do sistema).
case "$NAME" in
  nvme*|mmcblk*) die "$BASE parece disco interno (nvme/mmc). Abortando por seguranca." ;;
esac
# 2. So aceita dispositivo removivel OU com transporte USB.
REMOVABLE="$(cat "/sys/block/$NAME/removable" 2>/dev/null || echo 0)"
TRAN="$(lsblk -ndo TRAN "$BASE" 2>/dev/null || echo '')"
if [ "$REMOVABLE" != "1" ] && [ "$TRAN" != "usb" ]; then
  die "$BASE nao e removivel nem USB (TRAN='$TRAN'). Abortando por seguranca."
fi
# 3. Recusa se alguma particao do device estiver montada em ponto critico.
while read -r mp; do
  case "$mp" in
    /|/boot|/boot/efi|/home|/mnt/hdauxiliar)
      die "$BASE tem particao montada em '$mp' (sistema!). Abortando." ;;
  esac
done < <(lsblk -nro MOUNTPOINT "$BASE" | grep -v '^$' || true)

# ---- CONFIRMACAO ------------------------------------------------------------
echo ">> Alvo: $BASE"
lsblk -o NAME,SIZE,TYPE,TRAN,LABEL,MOUNTPOINT "$BASE"
echo
echo "!! ISSO APAGA TODAS AS PARTICOES E DADOS DE $BASE de forma IRREVERSIVEL."
if [ "$FORCE" != "1" ]; then
  read -r -p "Digite o nome do device para confirmar (ex.: $NAME): " ans
  [ "$ans" = "$NAME" ] || die "confirmacao nao confere ('$ans' != '$NAME'). Abortando."
fi

# ---- LIBERA O DEVICE --------------------------------------------------------
echo ">> desligando swap em $BASE (se houver)..."
while read -r part; do
  swapoff "/dev/$part" 2>/dev/null && echo "   swapoff /dev/$part" || true
done < <(lsblk -nro NAME,TYPE "$BASE" | awk '$2=="part"{print $1}')

echo ">> desmontando particoes de $BASE..."
# desmonta da mais profunda p/ a mais rasa
for part in $(lsblk -nro NAME,TYPE "$BASE" | awk '$2=="part"{print $1}'); do
  for mp in $(findmnt -nro TARGET "/dev/$part" 2>/dev/null || true); do
    umount -f "/dev/$part" 2>/dev/null && echo "   umount /dev/$part ($mp)" \
      || umount -l "/dev/$part" 2>/dev/null && echo "   umount -l /dev/$part ($mp)" || true
  done
done

echo ">> matando processos que ainda seguram $BASE (se houver)..."
fuser -k "$BASE"* 2>/dev/null || true
sleep 1

# ---- DESTRUICAO -------------------------------------------------------------
echo ">> apagando assinaturas de FS/particao (wipefs)..."
for part in $(lsblk -nro NAME,TYPE "$BASE" | awk '$2=="part"{print $1}'); do
  wipefs -a "/dev/$part" 2>/dev/null || true
done
wipefs -a "$BASE" 2>/dev/null || true

# Tamanho do disco em MiB para zerar tambem o final (backup GPT).
SECTORS="$(blockdev --getsz "$BASE")"
END_SEEK_MIB=$(( SECTORS / 2048 - 32 ))   # 512B*2048 = 1MiB; ultimos 32 MiB

echo ">> zerando os primeiros 32 MiB (MBR/tabela primaria)..."
dd if=/dev/zero of="$BASE" bs=1M count=32 conv=fsync status=none
if [ "$END_SEEK_MIB" -gt 0 ]; then
  echo ">> zerando os ultimos 32 MiB (backup GPT)..."
  dd if=/dev/zero of="$BASE" bs=1M seek="$END_SEEK_MIB" count=32 conv=fsync status=none 2>/dev/null || true
fi
sync

# ---- FORCA O KERNEL A RELER -------------------------------------------------
echo ">> forcando releitura da tabela de particoes..."
partx -d "$BASE" 2>/dev/null || true
blockdev --rereadpt "$BASE" 2>/dev/null || true
partprobe "$BASE" 2>/dev/null || true
udevadm settle 2>/dev/null || true
sync

echo
echo ">> PRONTO. $BASE limpo:"
lsblk -o NAME,SIZE,TYPE,TRAN,LABEL,MOUNTPOINT "$BASE"
echo
echo "Agora grave a imagem manualmente:"
echo "  sudo dd if=out/arch-tx9-busybox-video-x11.img of=$BASE bs=4M conv=fsync status=progress"
echo "  sync"
