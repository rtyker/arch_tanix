# Como fazer o build e gravar — Arch Linux (Tanix TX9)

Passo a passo do zero até o cartão/pendrive pronto para bootar.

## 0. Pré-requisitos (uma vez, host Arch x86_64)

```bash
sudo pacman -S --needed aarch64-linux-gnu-gcc aarch64-linux-gnu-binutils \
  aarch64-linux-gnu-glibc base-devel bc flex bison openssl pahole cpio \
  uboot-tools lzop curl parted dosfstools e2fsprogs util-linux \
  fakeroot mtools
```

> `mkimage` (uboot-tools) e `lzop` também já estão em `toolbin/bin/` — se não
> quiser instalá-los, aponte o `PATH` para lá: `export PATH="$PWD/toolbin/bin:$PATH"`.

## 1. Build (4 passos, nesta ordem)

```bash
cd /mnt/hdauxiliar/arch_tanix

./scripts/01-build-kernel.sh                 # kernel 6.12 -> Image, dtbs, modules
./scripts/02-package-kernel.sh               # Image -> lzo -> uImage (out/KERNEL)
./scripts/03-fetch-rootfs.sh                 # baixa rootfs ArchLinuxARM aarch64
FLAVOR=minimal ./scripts/04-build-image-rootless.sh   # monta out/arch-tx9.img
```

Ao final: `>> imagem pronta: .../out/arch-tx9.img`.

### Escolha do flavor (passo 4)

```bash
FLAVOR=minimal ./scripts/04-build-image-rootless.sh   # só CLI: curl, nano, ssh… (padrão)
FLAVOR=video   ./scripts/04-build-image-rootless.sh   # Wayland + wayfire (GPU panfrost)
FLAVOR=lxqt    ./scripts/04-build-image-rootless.sh   # desktop X11 LXQt completo
```

Definições em `config/flavors/`. Variáveis opcionais:
- `DTB=meson-gxm-s912-libretech-pc.dtb`  dtb alternativo
- `IMG_SIZE_MB=4096`                     tamanho da imagem (flavors gráficos: ≥4096)

### Alternativa com root (em vez do rootless)
```bash
sudo FLAVOR=minimal ./scripts/04-build-image.sh
```

## 2. Descobrir o dispositivo certo (NÃO erre aqui)

Conecte o cartão/pendrive e rode:

```bash
lsblk -o NAME,SIZE,TYPE,TRAN,MOUNTPOINTS -e7
```

Identifique pelo **tamanho** e por `TRAN=usb`. Os discos do sistema são `nvme*`
— **nunca** grave neles. Anote o nome (ex.: `/dev/sda`).

Se houver partições montadas do alvo, desmonte antes:

```bash
sudo umount /dev/sdX*   # troque sdX pelo seu dispositivo
```

## 3. Gravar (apaga TUDO no dispositivo)

```bash
sudo dd if=out/arch-tx9.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

> ⚠️ Troque `/dev/sdX` pelo dispositivo do passo 2. O `dd` é destrutivo e
> irreversível — confira duas vezes antes de dar Enter.

## 4. Bootar no box

1. Insere o cartão/pendrive no Tanix TX9.
2. **Conecte o cabo Ethernet** — o 1º boot precisa de rede (veja abaixo).
3. Segura o reset (dentro do conector AV, com um palito) e liga.
4. O kernel monta a ext4 (`root=LABEL=TX9ROOT`) e sobe o ArchLinuxARM.

### Primeiro boot: instalação dos pacotes do flavor

Os pacotes **não** vêm na imagem; são instalados na própria box no 1º boot pelo
serviço `tx9-firstboot` (`pacman -Syu` da lista em `/etc/tx9/flavor.pkgs`).
Por isso o **Ethernet** é obrigatório no primeiro boot (Wi-Fi só depois).

- Acompanhe pelo console serial (`ttyAML0,115200n8`) ou em `/var/log/tx9-firstboot.log`.
- Os flavors `video`/`lxqt` baixam centenas de MB — pode levar vários minutos.
- Se o pacman falhar, o serviço se mantém e tenta de novo no próximo boot.

### Login

- Usuário padrão ArchLinuxARM: **`alarm` / `alarm`**  (root: **`root` / `root`**)
- SSH já fica habilitado (`sshd`); descubra o IP pelo seu roteador ou via serial.

### Diagnóstico rápido (no box)
```bash
journalctl -u tx9-firstboot      # como foi a instalação do flavor
cat /etc/tx9/flavor.name         # qual flavor está nesta imagem
journalctl -u systemd-networkd   # rede
cat /proc/cmdline                # bootargs do u-boot
ls /dev/dri                      # GPU (panfrost) presente?
```

Sem o cartão, o box volta ao Android normalmente.
