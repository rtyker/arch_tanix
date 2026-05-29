#!/bin/bash
# Baixa o rootfs generico aarch64 do Arch Linux ARM.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
TARBALL="$BUILD/ArchLinuxARM-aarch64-latest.tar.gz"
URL="http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz"

mkdir -p "$BUILD"
if [ ! -f "$TARBALL" ]; then
  echo ">> baixando rootfs ArchLinuxARM aarch64"
  curl -L --fail -o "$TARBALL" "$URL"
fi
echo ">> rootfs em $TARBALL ($(du -h "$TARBALL" | cut -f1))"
