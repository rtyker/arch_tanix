# Tiny Failsafe - Boot Ultra-Rápido com BusyBox (Tanix TX9 Pro)

Este subprojeto contém scripts e arquivos para gerar um ambiente de recuperação/diagnóstico (failsafe) ultra-rápido rodando **100% na memória RAM**, sem qualquer dependência de partição rootfs ext4 ou cartão SD particionado de forma complexa.

O sistema dá boot completo e cai direto no prompt de comando em **menos de 5 segundos**!

## Características do Tiny Failsafe
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

---

## Solução de Problemas: Bootloop no Serial (Erro LZO -6 / -8)

Se você compilar o projeto e a console serial mostrar um bootloop infinito com a mensagem:
`Uncompressing Kernel Image ... LZO: uncompress or overwrite error -6 (ou -8) - must RESET board to recover`

### Causa Real do Problema
O U-Boot de fábrica carrega o arquivo `KERNEL` comprimido na memória RAM em `0x01080000` (`loadaddr`). A descompressão do kernel ocorre para a área definida em `LOAD=0x02000000` (32MB).
*   Se o tamanho do kernel comprimido exceder **15.5 MB** (`16252864` bytes), a parte final do container carregado na RAM irá além do endereço `0x02000000`.
*   Durante a descompressão, o U-Boot começará a descompactar e escrever dados em `0x02000000`, **sobrescrevendo os próprios dados comprimidos** que ele ainda não leu!
*   Isso corrompe o fluxo LZO, resultando em falhas de descompressão (`error -6` ou `error -8`) e forçando o reinício (bootloop).

### Como Resolver
1.  **Não esqueça de rodar o `prune-config.sh`**:
    O kernel padrão (configuração principal) é grande demais. Para o `tiny-failsafe`, você **deve** rodar `./tiny-failsafe/prune-config.sh` antes de `./tiny-failsafe/build-kernel.sh` para desabilitar drivers desnecessários e reduzir o tamanho final da imagem.
2.  **Verifique os Avisos do Build**:
    O script `package-kernel.sh` agora possui uma validação de segurança. Se o tamanho for crítico, ele emitirá um aviso bem visível no terminal.
3.  **Ajuste o LOAD Address (Se necessário)**:
    Se você realmente precisar de um kernel maior para o failsafe, altere a variável `LOAD` em `tiny-failsafe/package-kernel.sh` de `0x02000000` para `0x03000000` (ou outro endereço alinhado em 2MB e seguro na faixa de RAM acessível).

