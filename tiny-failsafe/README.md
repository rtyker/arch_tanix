# Tiny Failsafe - Boot Ultra-Rápido com BusyBox (Tanix TX9 Pro)

Este subprojeto contém scripts e arquivos para gerar um ambiente de recuperação/diagnóstico (failsafe) ultra-rápido rodando **100% na memória RAM**, sem qualquer dependência de partição rootfs ext4 ou cartão SD particionado de forma complexa.

O sistema dá boot completo e cai direto no prompt de comando em **menos de 5 segundos**!

## Características do Tiny Failsafe
1. **Infraestrutura em RAM (Initramfs)**: O BusyBox completo é embutido diretamente como `initramfs` dentro da imagem do kernel Linux.
2. **Sem Módulos de Kernel (`CONFIG_MODULES=n`)**: Todos os drivers essenciais (Display DRM Meson, USB Host XHCI, USB HID, Clocks da plataforma Amlogic, Teclado USB) são compilados de forma **monolítica** (`=y`) direto no kernel, garantindo que o hardware funcione sem depender de carregamento de arquivos do disco.
3. **Altamente Otimizado**: Drivers de outras placas de SoC (Qualcomm, Tegra, Rockchip, Apple, etc.), placas de vídeo pesadas (Nouveau, AMD, Intel), suporte a rede física, som, virtualização e sistemas de arquivos pesados (Btrfs, XFS, F2FS, NFS, CIFS) foram completamente desabilitados, deixando o kernel enxuto (~14MB comprimido em LZO).
4. **Console Duplo**: O console interativo do BusyBox abre simultaneamente na TV (via HDMI, tty1) e na console serial (UART, ttyAML0).

---

## Estrutura de Arquivos

* `build-busybox.sh`: Baixa o BusyBox, compila de forma estática para `aarch64` e popula a árvore de diretórios do initramfs.
* `initramfs-root/`: Esqueleto do sistema de arquivos raiz temporário (contém o binário `busybox` e o script de inicialização principal `/init`).
* `prune-config.sh`: Configura o kernel aplicando as otimizações de poda de tamanho (desativa SoCs, som, virtualização, btrfs, rede física, etc.).
* `build-kernel.sh`: Compila o kernel monolítico com o initramfs embutido.
* `package-kernel.sh`: Compacta o kernel cru em LZO e gera o contêiner `uImage` compatível com o U-Boot (`out/KERNEL`).
* `build-image.sh`: Cria a imagem final `tiny-failsafe.img` com uma única partição FAT32 de 32MB contendo o `KERNEL`, os scripts de bootloader, a árvore de dispositivos (`meson-gxm-s912-libretech-pc.dtb`) e o `uEnv.ini`.

---

## Como Compilar e Gerar a Imagem

Execute os scripts a partir da raiz do repositório `/mnt/hdauxiliar/arch_tanix`:

```bash
# 1. Compilar o BusyBox e estruturar o initramfs
./tiny-failsafe/build-busybox.sh

# 2. Configurar o Kernel (aplica a poda de drivers)
./tiny-failsafe/prune-config.sh

# 3. Compilar o Kernel
./tiny-failsafe/build-kernel.sh

# 4. Empacotar o Kernel (Gera tiny-failsafe/out/KERNEL)
./tiny-failsafe/package-kernel.sh

# 5. Gerar a imagem de boot (Gera tiny-failsafe/out/tiny-failsafe.img)
./tiny-failsafe/build-image.sh
```

---

## Como Gravar no Cartão SD / USB

Identifique a sua mídia (ex: `/dev/sda`) e execute:

```bash
sudo dd if=tiny-failsafe/out/tiny-failsafe.img of=/dev/sda bs=4M conv=fsync status=progress
```

Insira o cartão no Tanix TX9 Pro, pressione e segure o botão de Reset (dentro do conector AV de áudio analógico) usando um palito e ligue o cabo de energia.

---

## Diagnóstico e Monitoramento Serial

O bootloader U-Boot de fábrica se comunica a **115200** baud rate. Para monitorar o boot da placa em tempo real pelo seu computador host:

```bash
picocom -b 115200 /dev/ttyUSB0
```
*(Nota: Certifique-se de que não há outros processos competindo pela leitura da `/dev/ttyUSB0` para evitar caracteres corrompidos).*
