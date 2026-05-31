# Ram Failsafe - Boot Ultra-Rápido com BusyBox (Tanix TX9 Pro)

Este subprojeto contém scripts e arquivos para gerar um ambiente de recuperação/diagnóstico (ram-failsafe) ultra-rápido rodando **100% na memória RAM**, sem qualquer dependência de partição rootfs ext4 ou cartão SD particionado de forma complexa.

O sistema dá boot completo e cai direto no prompt de comando em **menos de 5 segundos**!

## Características do Ram Failsafe
1. **Infraestrutura em RAM (Initramfs)**: Um BusyBox **enxuto** (gerado via `allnoconfig` + uma lista mínima de applets — shell `ash`, utilitários de arquivo/sistema, rede básica e `setsid`) é compilado estaticamente para `aarch64` e embutido diretamente como `initramfs` dentro da imagem do kernel Linux.
2. **Sem Módulos de Kernel (`CONFIG_MODULES=n`)**: Todos os drivers essenciais (Display DRM Meson, USB Host XHCI, USB HID, Clocks da plataforma Amlogic, Teclado USB) são compilados de forma **monolítica** (`=y`) direto no kernel, garantindo que o hardware funcione sem depender de carregamento de arquivos do disco.
3. **Altamente Otimizado**: Drivers de outras placas de SoC (Qualcomm, Tegra, Rockchip, Apple, etc.), placas de vídeo pesadas (Nouveau, AMD, Intel), suporte a rede física, som, virtualização e sistemas de arquivos pesados (Btrfs, XFS, F2FS, NFS, CIFS) foram completamente desabilitados, deixando o kernel enxuto (~14MB comprimido em LZO).
4. **Console Duplo**: O console interativo do BusyBox abre simultaneamente na TV (via HDMI, tty1) e na console serial (UART, ttyAML0).

---

## Estrutura de Arquivos

* `build-busybox.sh`: Baixa o BusyBox, configura um conjunto mínimo de applets (`allnoconfig` + enables seletivos, incluindo o `setsid` exigido pelo `/init`), compila de forma estática para `aarch64` e popula a árvore de diretórios do initramfs.
* `initramfs-root/`: Esqueleto do sistema de arquivos raiz temporário (contém o binário `busybox` e o script de inicialização principal `/init`).
* `prune-config.sh`: Configura o kernel aplicando as otimizações de poda de tamanho (desativa SoCs, som, virtualização, btrfs, rede física, etc.).
* `build-kernel.sh`: Compila o kernel monolítico com o initramfs embutido.
* `build-image.sh`: Cria a imagem final `ram-failsafe.img` com uma única partição FAT32 de 32MB contendo o `KERNEL`, os scripts de bootloader, a árvore de dispositivos (`meson-gxm-s912-libretech-pc.dtb`) e o `uEnv.ini`.

---

## Como Compilar e Gerar a Imagem

Execute os scripts a partir da raiz do repositório `/mnt/hdauxiliar/arch_tanix`:

```bash
# 1. Compilar o BusyBox e estruturar o initramfs
./ram-failsafe/build-busybox.sh

# 2. Configurar o Kernel (aplica a poda de drivers)
./ram-failsafe/prune-config.sh

# 3. Compilar o Kernel
./ram-failsafe/build-kernel.sh

# 4. Empacotar o Kernel (Gera ram-failsafe/out/KERNEL)
./ram-failsafe/package-kernel.sh

# 5. Gerar a imagem de boot (Gera ram-failsafe/out/ram-failsafe.img)
./ram-failsafe/build-image.sh
```

---

## Como Gravar no Cartão SD / USB

Identifique a sua mídia (ex: `/dev/sda`) e execute:

```bash
sudo dd if=ram-failsafe/out/ram-failsafe.img of=/dev/sda bs=4M conv=fsync status=progress
```

Insira o cartão no Tanix TX9 Pro, pressione e segure o botão de Reset (dentro do conector AV de áudio analógico) usando um palito e ligue o cabo de energia.

---

## Diagnóstico e Monitoramento Serial

O bootloader U-Boot de fábrica se comunica a **115200** baud rate. Para monitorar o boot da placa em tempo real pelo seu computador host:

```bash
picocom -b 115200 /dev/ttyUSB0
```
*(Nota: Certifique-se de que não há outros processos competindo pela leitura da `/dev/ttyUSB0` para evitar caracteres corrompidos).*

---

## Endereço de carga (`LOAD`) e por que o uImage é **sem compressão**

O `package-kernel.sh` empacota o `Image` cru como uImage **sem compressão** (`mkimage -C none`)
com `LOAD = ENTRY = 0x03000000`. O fluxo no boot é:

1.  O U-Boot de fábrica lê o arquivo `KERNEL` do FAT para a RAM em `0x01080000` (`loadaddr`).
2.  Como o uImage é `-C none`, o `bootm` apenas **copia** o payload de `loadaddr` para `LOAD`
    (`0x03000000`) — não há etapa de descompressão.

A única regra a respeitar: **as faixas de origem e destino não podem se sobrepor**. Com o
kernel atual (~19,4 MB), origem `0x01080000`–`~0x023E6xxx` e destino `0x03000000`–`~0x0434xxxx`
ficam bem separadas, então não há corrupção.

> **Histórico:** versões antigas usavam uImage comprimido em LZO com `LOAD=0x02000000`. Quando
> o kernel comprimido passava de ~15,5 MB, a área de descompressão (`0x02000000`) invadia o
> próprio container ainda não lido, corrompendo o stream LZO (`uncompress or overwrite error -6/-8`,
> bootloop). Trocar para `-C none` + `LOAD=0x03000000` eliminou essa classe de erro.

### Se o kernel crescer demais
1.  **Rode sempre o `prune-config.sh`** antes do `build-kernel.sh`: ele desabilita drivers de
    outros SoCs, som, virtualização, FS pesados etc., mantendo o `Image` enxuto.
2.  **Se ainda assim o `Image` ficar grande**, suba o `LOAD` em `ram-failsafe/package-kernel.sh`
    (ex.: `0x04000000`) — escolha um endereço alinhado em 2 MB, dentro da RAM acessível e que
    **não** sobreponha a faixa carregada em `loadaddr` (`0x01080000`).

