# Arch Linux para Tanix TX9 (Amlogic S912 / meson-gxm)

Arch Linux ARM aarch64 simples para o box Tanix TX9 Pro, inspirado no esquema de
boot Amlogic-ng do LibreELEC/CoreELEC. Boota de **cartão SD/USB** via método
toothpick, **sem tocar no eMMC/Android** interno.

## Hardware alvo (confirmado no box de referência)

- SoC: Amlogic **S912** (`amlogic,meson-gxm`), octa-core Cortex-A53
- RAM: 3 GB
- GPU: Mali-T820 (panfrost no mainline; `/dev/dri/card*` + `renderD128`)
- Console serial: `ttyAML0,115200n8`
- DTB: `meson-gxm-tx9-pro.dtb` (alt.: `meson-gxm-s912-libretech-pc.dtb`, usado pelo
  LibreELEC de fábrica neste box)

## Cadeia de boot (replicada do LibreELEC)

1. U-boot de fábrica (toothpick) → `aml_autoscript` configura `bootcmd`.
2. `s905_autoscript` varre mmc/usb, carrega `KERNEL` + `uEnv.ini` + dtb e faz `bootm`.
3. `boot.scr` (script distro) importa `uEnv.ini` (define `dtb_name` e `bootargs`),
   carrega `KERNEL`, dtb, e `bootm`.

Como **não existe `u-boot.ext`** neste box, quem executa `bootm` é o u-boot de
fábrica → o kernel precisa ser **uImage legacy** (não Image cru).

Formato do KERNEL (lido do uImage do LibreELEC):
`arch=arm64 os=linux type=kernel comp=lzo load=0x01d80000 entry=0x01d80000`.

## Layout do cartão (MBR)

- `p1` FAT32 (256 MB): `KERNEL`, `boot.scr`, `*_autoscript`, `uEnv.ini`, `dtb/`
- `p2` ext4: rootfs ArchLinuxARM + módulos do kernel

## Build (host x86_64 com cross aarch64)

```bash
./scripts/01-build-kernel.sh    # baixa+compila kernel 6.12 LTS (Image, dtbs, modules)
./scripts/02-package-kernel.sh  # Image -> lzo -> uImage (out/KERNEL)   [precisa uboot-tools, lzop]
./scripts/03-fetch-rootfs.sh    # baixa rootfs ArchLinuxARM aarch64
sudo ./scripts/04-build-image.sh # monta out/arch-tx9.img                [precisa root]
# OU, sem sudo:
./scripts/04-build-image-rootless.sh  # mesma imagem via fakeroot+mke2fs -d+mtools
```

## Gravar e bootar

```bash
sudo dd if=out/arch-tx9.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Insere o cartão, segura o reset (dentro do conector AV) e liga — boota o Arch.
Sem o cartão, o box volta ao Android normalmente.

## Dependências do host (Arch Linux x86_64)

Nomes de pacotes do repositório oficial do Arch, agrupados por etapa do build.

### 1. Compilar o kernel — `01-build-kernel.sh`
- `aarch64-linux-gnu-gcc` — compilador cross (puxa `aarch64-linux-gnu-binutils`
  e `aarch64-linux-gnu-glibc` como dependências)
- `base-devel` — `make`, `gcc` do host, `patch`, etc.
- `bc`, `flex`, `bison` — exigidos pelo build do kernel
- `openssl` — geração/assinatura de certificados do kernel
- `pahole` — gera info BTF se `CONFIG_DEBUG_INFO_BTF` estiver ligado
- `cpio`, `perl`, `tar`, `gzip`, `xz` — normalmente já vêm no grupo `base`

Instalação:
```bash
sudo pacman -S --needed aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils \
  aarch64-linux-gnu-glibc base-devel bc flex bison openssl pahole cpio
```

### 2. Empacotar o uImage — `02-package-kernel.sh`
- `uboot-tools` — fornece `mkimage`
- `lzop` — compressão LZO (puxa `lzo`)

```bash
sudo pacman -S --needed uboot-tools lzop
```

### 3. Baixar o rootfs — `03-fetch-rootfs.sh`
- `curl`

### 4. Montar a imagem de SD — `04-build-image.sh` (precisa de root)
- `parted` — particionamento MBR
- `dosfstools` — `mkfs.vfat`
- `e2fsprogs` — `mkfs.ext4`, `blkid`
- `util-linux` — `losetup`, `mount`, `blkid`

```bash
sudo pacman -S --needed parted dosfstools e2fsprogs util-linux
```

### 4b. Montar a imagem SEM root — `04-build-image-rootless.sh`
Alternativa que dispensa `sudo` (não usa `losetup`/`mount`):
- `fakeroot` — finge uid/gid 0 ao extrair o rootfs (mantém dono `root:root`)
- `mtools` — `mcopy`/`mmd` populam a partição FAT sem montar
- `e2fsprogs` (≥ 1.43) — `mke2fs -d` popula a partição ext4 a partir de um diretório
- `parted`, `dosfstools`

```bash
sudo pacman -S --needed fakeroot mtools e2fsprogs parted dosfstools
```

> Os binários `mkimage` e `lzop` também podem ser obtidos sem instalar nada no
> sistema: baixe os pacotes com `pacman -Sp <pkg>` e extraia só `usr/bin/` com
> `tar`, apontando o `PATH` para a pasta resultante (ver `toolbin/`).
