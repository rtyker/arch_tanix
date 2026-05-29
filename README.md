# Arch Linux para Tanix TX9 (Amlogic S912 / meson-gxm)

Arch Linux ARM aarch64 simples para o box Tanix TX9 Pro, inspirado no esquema de
boot Amlogic-ng do LibreELEC/CoreELEC. Boota de **cartão SD/USB** via método
toothpick, **sem tocar no eMMC/Android** interno.

## Hardware alvo (confirmado no box de referência)

- SoC: Amlogic **S912** (`amlogic,meson-gxm`), octa-core Cortex-A53
- RAM: 3 GB
- GPU: Mali-T820 (panfrost no mainline; `/dev/dri/card*` + `renderD128`)
- Console serial: `ttyAML0,115200n8` (UART AO em `0xc81004c0`; `earlycon=meson,0xc81004c0`)
- DTB: **`meson-gxm-s912-libretech-pc.dtb`**, gerado pelo **nosso** kernel
  (`out/dtb/`) — é o modelo que este box aceita (o LibreELEC de fábrica também
  boota com ele). **Não** reutilize o `tx9-pro` do LibreELEC: é de outro kernel
  (downstream) e nem existe no mainline 6.12; casar dtb alheio com o nosso kernel
  causava pânico precoce.

## Cadeia de boot (replicada do LibreELEC)

1. U-boot de fábrica (toothpick) → `aml_autoscript` configura `bootcmd`.
2. `s905_autoscript` varre mmc/usb, carrega `KERNEL` + `uEnv.ini` + dtb e faz `bootm`.
3. `boot.scr` (script distro) importa `uEnv.ini` (define `dtb_name` e `bootargs`),
   carrega `KERNEL`, dtb, e `bootm`.

Como **não existe `u-boot.ext`** neste box (confirmado por serial), quem executa
`bootm` é o u-boot de fábrica → o kernel precisa ser **uImage legacy** (não Image cru).

Formato do KERNEL: uImage legacy `arch=arm64 os=linux type=kernel comp=lzo`,
com **`load=entry=0x02000000`** (ver `scripts/02-package-kernel.sh`). O destino
fica logo acima do container do uImage e na faixa de RAM que o u-boot de fábrica
alcança — `0x01d80000` (LibreELEC) não cabe porque nosso kernel comprimido é maior,
e endereços altos (`0x08000000`) o u-boot descomprime mas… na prática o que travava
o boot **não** era isso: era o `root=` (veja abaixo).

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

O passo 04 aceita `FLAVOR=` para escolher o conjunto de pacotes (ver abaixo):

```bash
FLAVOR=minimal ./scripts/04-build-image-rootless.sh   # padrao
FLAVOR=video   ./scripts/04-build-image-rootless.sh
FLAVOR=lxqt    ./scripts/04-build-image-rootless.sh
```

## Flavors

Os pacotes de cada flavor **não** são instalados no host (rootfs é aarch64).
A imagem leva uma lista de pacotes embarcada em `/etc/tx9/flavor.pkgs` e um
serviço systemd oneshot **`tx9-firstboot`** que, no **1º boot**, inicializa o
keyring, roda `pacman -Syu` com essa lista, habilita os serviços do flavor e se
desabilita. Definições em `config/flavors/` (`base.pkgs` é comum a todos):

| Flavor     | O que instala | Gráfico |
|------------|---------------|---------|
| `failsafe` | **nada** — só o rootfs base + autologin root no serial/HDMI. Mínimo p/ diagnóstico (sem rede, sem firstboot) | nenhum |
| `minimal`  | só o `base`: curl, nano, vim, sudo, ssh, iwd, … | nenhum |
| `video`    | base + Mesa/panfrost + **wayfire** (Wayland/GLES2) + greetd | Wayland acelerado |
| `lxqt`     | base + Xorg + Mesa + **LXQt** + sddm | desktop X11 completo |

### Ajustes aplicados nos flavors reais (a partir do `minimal`)

`apply-flavor.sh`/`tx9-firstboot` configuram automaticamente (o `failsafe` fica
de fora destes, por ser mínimo):

- **root por PARTUUID** (`root=PARTUUID=54583900-02`) — o kernel resolve sem
  initramfs; `LABEL=`/`UUID=` **não** funcionam sem initramfs (era a causa real do
  "bootloop": pânico `VFS: unable to mount root`).
- **Auto-expansão do root** no 1º boot (`tx9-growroot`): cresce a `p2` + ext4 para
  ocupar todo o cartão/pendrive (via `sfdisk`+`partx`+`resize2fs`, sem pacotes extras).
- **Locale** `pt_BR.UTF-8` (gerado no 1º boot por `locale-gen`).
- **Fonte de console** maior (`latarcyrheb-sun32`) para a TV.
- **NTP do Brasil** via `systemd-timesyncd` (`a/b/c.ntp.br`).
- **SSH root** habilitado (`PermitRootLogin yes`); login `root`/`root`.
- **pacman**: `DisableSandboxFilesystem` (kernel sem `CONFIG_SECURITY_LANDLOCK`).

Escolha do stack gráfico: a Mali-T820 com **panfrost** só expõe **GLES2/3** (sem
OpenGL desktop). Por isso `video` usa um compositor **wlroots (wayfire)**, que
fala GLES2 nativamente e usa a GPU de verdade; `lxqt` roda em X11 (compositing
por Xrender, sem depender de GL desktop). Cinnamon foi descartado por exigir
compositing OpenGL — cairia em software (llvmpipe), inviável no A53.

> **1º boot precisa de rede.** O build habilita `systemd-networkd` com DHCP
> cabeado (`en*/eth*`), então conecte o **Ethernet** no primeiro boot. Wi-Fi
> (brcmfmac) exige `linux-firmware` + `iwctl` e só fica pronto depois. Acompanhe
> em `/var/log/tx9-firstboot.log`. Os flavors gráficos baixam centenas de MB —
> use `IMG_SIZE_MB>=4096` (padrão).

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

## Failsafe Ultra-Rápido Alternativo (BusyBox em RAM)

Para testes rápidos ou diagnóstico de hardware de baixo nível, existe o subprojeto **[Tiny Failsafe](file:///mnt/hdauxiliar/arch_tanix/tiny-failsafe/README.md)** na pasta `tiny-failsafe/`.

Ele compila o kernel de forma monolítica com o BusyBox embutido em `initramfs`, gerando um boot de menos de 5 segundos que roda 100% na memória RAM a partir de uma única partição FAT32 de 32MB. Veja os detalhes em [tiny-failsafe/README.md](file:///mnt/hdauxiliar/arch_tanix/tiny-failsafe/README.md).

