#!/bin/bash
# tx9-firstboot.sh — instalador de primeiro boot do flavor TX9.
# Roda UMA vez (oneshot): inicializa o keyring, instala os pacotes do flavor,
# habilita as unidades declaradas, ajusta o default target e se desabilita.
# Idempotente: se o pacman falhar, mantem o servico para tentar no proximo boot.
set -uo pipefail

TX9=/etc/tx9
STAMP=/var/lib/tx9-firstboot.done
LOG=/var/log/tx9-firstboot.log

[ -f "$STAMP" ] && exit 0
exec >>"$LOG" 2>&1
echo "===== tx9-firstboot $(date -u) flavor=$(cat "$TX9/flavor.name" 2>/dev/null || echo '?') ====="

# 1. keyring do ArchLinuxARM (necessario para o pacman validar pacotes)
if [ ! -e /etc/pacman.d/gnupg/trustdb.gpg ]; then
  echo ">> pacman-key --init"
  pacman-key --init
fi
echo ">> pacman-key --populate archlinuxarm"
pacman-key --populate archlinuxarm || true

# 1b. gera os locales descomentados em /etc/locale.gen (ex.: pt_BR.UTF-8).
#     Roda antes do pacman: nao precisa de rede e garante LANG mesmo se o
#     pacman falhar. (locale.conf=LANG=pt_BR.UTF-8 ja foi escrito no build.)
echo ">> locale-gen"
locale-gen || true

# 2. pacotes do flavor (base.pkgs + <flavor>.pkgs ja mesclados em flavor.pkgs)
# pega so o 1o token de cada linha (ignora comentarios inline e linhas vazias/#)
mapfile -t PKGS < <(awk 'NF && $1 !~ /^#/ {print $1}' "$TX9/flavor.pkgs" 2>/dev/null || true)
if [ "${#PKGS[@]}" -gt 0 ]; then
  echo ">> instalando ${#PKGS[@]} pacotes: ${PKGS[*]}"
  if ! pacman -Syu --noconfirm --needed "${PKGS[@]}"; then
    echo "!! pacman falhou — servico mantido para nova tentativa no proximo boot"
    exit 1
  fi
fi

# 3. unidades habilitadas pelo flavor (base.enable + <flavor>.enable)
if [ -f "$TX9/flavor.enable" ]; then
  while read -r unit _; do
    [ -z "$unit" ] && continue
    case "$unit" in \#*) continue ;; esac
    echo ">> systemctl enable $unit"
    systemctl enable "$unit" || true
  done < "$TX9/flavor.enable"
fi

# 4. default target (ex.: graphical.target nos flavors de desktop)
TARGET=""
if [ -f "$TX9/flavor.target" ]; then
  TARGET="$(head -n1 "$TX9/flavor.target")"
  if [ -n "$TARGET" ]; then
    echo ">> systemctl set-default $TARGET"
    systemctl set-default "$TARGET" || true
  fi
fi

# 5. conclui e remove o proprio servico do boot
touch "$STAMP"
echo ">> concluido — desabilitando tx9-firstboot.service"
systemctl disable tx9-firstboot.service || true

# 6. sobe o ambiente sem exigir reboot (best-effort)
if [ -n "$TARGET" ]; then
  echo ">> isolando $TARGET"
  systemctl isolate "$TARGET" || true
fi
echo "===== fim ====="
