#!/bin/bash
# apply-flavor.sh — injeta um flavor num diretorio de rootfs ja extraido.
# Chamado pelos scripts 04-build-image*.sh (no contexto fakeroot, no rootless).
# Nao instala pacotes aqui: apenas prepara os metadados + o servico de 1o boot
# (tx9-firstboot) que roda o pacman na propria box.
#
#   apply-flavor.sh <ROOTDIR> <FLAVOR> <REPO_ROOT>
set -euo pipefail

ROOTDIR="${1:?uso: apply-flavor.sh <ROOTDIR> <FLAVOR> <REPO_ROOT>}"
FLAVOR="${2:?falta o nome do flavor}"
REPO="${3:?falta o REPO_ROOT}"

FLAVDIR="$REPO/config/flavors"
FB="$REPO/scripts/firstboot"

[ -d "$ROOTDIR" ]                  || { echo "apply-flavor: ROOTDIR inexistente: $ROOTDIR"; exit 1; }
[ -f "$FLAVDIR/$FLAVOR.pkgs" ]     || { echo "apply-flavor: flavor desconhecido '$FLAVOR' (sem $FLAVOR.pkgs)"; exit 1; }
[ -f "$FB/tx9-firstboot.sh" ]      || { echo "apply-flavor: falta $FB/tx9-firstboot.sh"; exit 1; }

# flavor "failsafe": se existir <flavor>.nofirstboot, NAO instala o servico de
# 1o boot e NAO configura rede — sobe so o rootfs base ate um shell.
NOFIRSTBOOT=0
[ -f "$FLAVDIR/$FLAVOR.nofirstboot" ] && NOFIRSTBOOT=1

echo ">> aplicando flavor '$FLAVOR'$( [ "$NOFIRSTBOOT" = 1 ] && echo ' (nofirstboot: sem tx9-firstboot e sem rede)')"

# ---------------------------------------------------------------------------
# 1. metadados em /etc/tx9 (lidos pelo tx9-firstboot na box)
# ---------------------------------------------------------------------------
mkdir -p "$ROOTDIR/etc/tx9"
echo "$FLAVOR" > "$ROOTDIR/etc/tx9/flavor.name"

# lista de pacotes = base.pkgs + <flavor>.pkgs (comentarios preservados)
{
  echo "# flavor: $FLAVOR  (base.pkgs + $FLAVOR.pkgs)"
  cat "$FLAVDIR/base.pkgs"
  echo
  cat "$FLAVDIR/$FLAVOR.pkgs"
} > "$ROOTDIR/etc/tx9/flavor.pkgs"

# unidades a habilitar = base.enable + <flavor>.enable
: > "$ROOTDIR/etc/tx9/flavor.enable"
[ -f "$FLAVDIR/base.enable" ]     && cat "$FLAVDIR/base.enable"     >> "$ROOTDIR/etc/tx9/flavor.enable"
[ -f "$FLAVDIR/$FLAVOR.enable" ]  && cat "$FLAVDIR/$FLAVOR.enable"  >> "$ROOTDIR/etc/tx9/flavor.enable"

# default target opcional do flavor
[ -f "$FLAVDIR/$FLAVOR.target" ]  && cp "$FLAVDIR/$FLAVOR.target" "$ROOTDIR/etc/tx9/flavor.target"

# ---------------------------------------------------------------------------
# 2. servico de primeiro boot (pulado no failsafe/nofirstboot)
# ---------------------------------------------------------------------------
if [ "$NOFIRSTBOOT" = 1 ]; then
  echo "   nofirstboot: pulando instalacao do tx9-firstboot.service"
else
  install -Dm755 "$FB/tx9-firstboot.sh"      "$ROOTDIR/usr/local/sbin/tx9-firstboot.sh"
  install -Dm644 "$FB/tx9-firstboot.service" "$ROOTDIR/etc/systemd/system/tx9-firstboot.service"
  mkdir -p "$ROOTDIR/etc/systemd/system/multi-user.target.wants"
  ln -sf ../tx9-firstboot.service \
    "$ROOTDIR/etc/systemd/system/multi-user.target.wants/tx9-firstboot.service"
fi

# ---------------------------------------------------------------------------
# 3. arquivos extras especificos do flavor (<flavor>.files/ -> raiz do rootfs)
# ---------------------------------------------------------------------------
if [ -d "$FLAVDIR/$FLAVOR.files" ]; then
  echo "   copiando $FLAVOR.files/ para o rootfs"
  cp -a "$FLAVDIR/$FLAVOR.files/." "$ROOTDIR/"
fi

# ---------------------------------------------------------------------------
# 4. rede para o 1o boot: systemd-networkd + resolved (DHCP cabeado, 0 pacotes)
#    (sao parte do systemd, ja presentes no rootfs base)
#    Pulado no failsafe/nofirstboot: o failsafe nao precisa de rede.
# ---------------------------------------------------------------------------
if [ "$NOFIRSTBOOT" = 1 ]; then
  echo "   nofirstboot: pulando configuracao de rede"
  echo ">> flavor '$FLAVOR' aplicado (failsafe: sem rede, autologin no shell)"
else
  mkdir -p "$ROOTDIR/etc/systemd/network"
  cat > "$ROOTDIR/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF

  link_unit() {  # link_unit <target>.wants <unidade>
    local wants="$1" unit="$2"
    mkdir -p "$ROOTDIR/etc/systemd/system/$wants"
    ln -sf "/usr/lib/systemd/system/$unit" \
      "$ROOTDIR/etc/systemd/system/$wants/$unit"
  }
  link_unit multi-user.target.wants    systemd-networkd.service
  link_unit sockets.target.wants       systemd-networkd.socket
  link_unit multi-user.target.wants    systemd-resolved.service
  link_unit network-online.target.wants systemd-networkd-wait-online.service

  # resolv.conf gerenciado pelo resolved
  ln -sf /run/systemd/resolve/stub-resolv.conf "$ROOTDIR/etc/resolv.conf"

  echo ">> flavor '$FLAVOR' aplicado (pacotes serao instalados no 1o boot)"
fi
