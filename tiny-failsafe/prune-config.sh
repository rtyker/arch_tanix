#!/bin/bash
# Poda a configuracao do kernel para o failsafe enxuto
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KVER="${KVER:-6.12.91}"
SRC="$ROOT/build/linux-$KVER"

if [ ! -d "$SRC" ]; then
  echo "FALTA fonte do kernel em $SRC."
  exit 1
fi

cd "$SRC"

echo ">> Gerando defconfig limpo"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
make defconfig

echo ">> Podando configuracao do kernel para o failsafe enxuto"

# Desativa suporte a modulos de kernel (forca compilacao monolitica)
./scripts/config --disable CONFIG_MODULES

# Mantem a infraestrutura de rede basica (essencial para Unix Sockets /dev/log etc)
# mas desativa todos os drivers fisicos (Ethernet, Wi-Fi, Bluetooth)
./scripts/config --enable CONFIG_NET
./scripts/config --enable CONFIG_UNIX
./scripts/config --disable CONFIG_WIRELESS
./scripts/config --disable CONFIG_WLAN
./scripts/config --disable CONFIG_BT
./scripts/config --disable CONFIG_ETHERNET

# Desabilita som e multimidia
./scripts/config --disable CONFIG_SOUND
./scripts/config --disable CONFIG_SND
./scripts/config --disable CONFIG_MEDIA_SUPPORT

# Desabilita virtualizacao
./scripts/config --disable CONFIG_VIRTUALIZATION
./scripts/config --disable CONFIG_KVM

# Desabilita sistemas de arquivos pesados desnecessarios (Btrfs, XFS, F2FS, NFS, CIFS)
./scripts/config --disable CONFIG_BTRFS_FS
./scripts/config --disable CONFIG_XFS_FS
./scripts/config --disable CONFIG_F2FS_FS
./scripts/config --disable CONFIG_NFS_FS
./scripts/config --disable CONFIG_CIFS

# Desabilita drivers de impressora e portas paralelas
./scripts/config --disable CONFIG_PRINTER
./scripts/config --disable CONFIG_USB_PRINTER
./scripts/config --disable CONFIG_PARPORT
./scripts/config --disable CONFIG_PARPORT_PC

# Desabilita BTF e debug pesado para compilar rapido e economizar espaco
./scripts/config --disable CONFIG_DEBUG_INFO_BTF
./scripts/config --disable CONFIG_DEBUG_KERNEL
./scripts/config --disable CONFIG_DEBUG_INFO
./scripts/config --disable CONFIG_DEBUG_FS
./scripts/config --disable CONFIG_SLUB_DEBUG
./scripts/config --disable CONFIG_FTRACE
./scripts/config --disable CONFIG_STACKTRACE

# Desativa AArch32 compatibility (executáveis de 32 bits)
./scripts/config --disable CONFIG_COMPAT

# Desativa ACPI (S912 usa apenas Device Tree)
./scripts/config --disable CONFIG_ACPI

# Desativa EFI e EFI Stub
./scripts/config --disable CONFIG_EFI
./scripts/config --disable CONFIG_EFI_STUB

# Desativa Kallsyms (economiza muito espaço na imagem binária)
./scripts/config --disable CONFIG_KALLSYMS
./scripts/config --disable CONFIG_KALLSYMS_ALL
./scripts/config --disable CONFIG_KALLSYMS_BASE_RELATIVE

# Desativa Gerenciamento de Energia (suspend e hibernação)
./scripts/config --disable CONFIG_SUSPEND
./scripts/config --disable CONFIG_HIBERNATION

# Desativa IKCONFIG (config embutida no kernel)
./scripts/config --disable CONFIG_IKCONFIG
./scripts/config --disable CONFIG_IKCONFIG_PROC

# Desativa outras famílias de SoC ARM64 (deixa apenas ARCH_MESON)
for arch in ACTIONS AIROHA SUNXI ALPINE APPLE BCM BCM2835 BCM_IPROC BCMBCA BRCMSTB BERLIN EXYNOS SPARX5 K3 LG1K HISI KEEMBAY MEDIATEK MVEBU NXP LAYERSCAPE MXC S32 MA35 NPCM QCOM REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER TEGRA TESLA_FSD SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE ZYNQMP; do
  ./scripts/config --disable "CONFIG_ARCH_$arch"
done

# Desativa suporte a PCI (não usado no S912, economiza muitos drivers)
./scripts/config --disable CONFIG_PCI

# Desativa drivers de GPU pesados (mantém apenas o DRM da Amlogic)
./scripts/config --disable CONFIG_DRM_NOUVEAU
./scripts/config --disable CONFIG_DRM_RADEON
./scripts/config --disable CONFIG_DRM_AMDGPU
./scripts/config --disable CONFIG_DRM_I915
./scripts/config --disable CONFIG_DRM_VIRTIOGPU
./scripts/config --disable CONFIG_DRM_VC4
./scripts/config --disable CONFIG_DRM_PANFROST
./scripts/config --disable CONFIG_DRM_LIMA

# Garante que os drivers necessarios para HDMI e teclado USB sao built-in (Y) e nao modulos (M)
enable_builtin() {
  ./scripts/config --enable "$1"
}

# DRM / HDMI Console
enable_builtin CONFIG_DRM
enable_builtin CONFIG_DRM_MESON
enable_builtin CONFIG_DRM_DW_HDMI
enable_builtin CONFIG_BACKLIGHT_CLASS_DEVICE
enable_builtin CONFIG_FRAMEBUFFER_CONSOLE
enable_builtin CONFIG_LOGO

# USB + Teclado USB
enable_builtin CONFIG_USB_SUPPORT
enable_builtin CONFIG_USB
enable_builtin CONFIG_USB_XHCI_HCD
enable_builtin CONFIG_USB_XHCI_PLATFORM
enable_builtin CONFIG_USB_EHCI_HCD
enable_builtin CONFIG_USB_OHCI_HCD
enable_builtin CONFIG_USB_DWC3
enable_builtin CONFIG_USB_DWC3_MESON_G12A
enable_builtin CONFIG_USB_HID
enable_builtin CONFIG_HID_GENERIC
enable_builtin CONFIG_INPUT
enable_builtin CONFIG_INPUT_KEYBOARD
enable_builtin CONFIG_KEYBOARD_ATKBD

# Configura Initramfs embarcado
./scripts/config --enable CONFIG_BLK_DEV_INITRAMFS
./scripts/config --set-str CONFIG_INITRAMFS_SOURCE "$ROOT/tiny-failsafe/initramfs-root"
./scripts/config --enable CONFIG_INITRAMFS_COMPRESSION_LZO
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_GZIP
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_BZIP2
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_LZMA
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_XZ
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_LZ4
./scripts/config --disable CONFIG_INITRAMFS_COMPRESSION_ZSTD

echo ">> Ajustando pendencias (make olddefconfig)"
make olddefconfig

echo ">> Kernel configurado com sucesso!"
