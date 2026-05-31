#!/bin/bash

# Script para conectar facilmente ao console serial via picocom
# Uso: ./connect-serial.sh [dispositivo] [baudrate]
# Padrão: /dev/ttyUSB0 115200

DEVICE="${1}"
BAUD="${2:-115200}"

# Verifica se o picocom está instalado
if ! command -v picocom >/dev/null 2>&1; then
    echo "Erro: O programa 'picocom' não está instalado."
    echo "Dica: Instale-o com o gerenciador de pacotes da sua distribuição:"
    if command -v pacman >/dev/null 2>&1; then
        echo "  sudo pacman -S picocom"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "  sudo apt install picocom"
    elif command -v dnf >/dev/null 2>&1; then
        echo "  sudo dnf install picocom"
    else
        echo "  Instale o pacote 'picocom' usando o gerenciador de pacotes do sistema."
    fi
    exit 1
fi

# Se não foi passado dispositivo, tenta detectar
if [ -z "$DEVICE" ]; then
    # Habilita nullglob para que globs sem correspondência expandam para vazio
    shopt -s nullglob
    DEVS=(/dev/ttyUSB* /dev/ttyACM*)
    shopt -u nullglob # Restaura
    
    if [ ${#DEVS[@]} -gt 0 ]; then
        DEVICE="${DEVS[0]}"
        echo "Auto-detectado: $DEVICE"
    else
        # Fallback para o comportamento padrão
        DEVICE="/dev/ttyUSB0"
    fi
fi

# Verifica se o dispositivo existe e é um dispositivo de caractere
if [ ! -c "$DEVICE" ]; then
    echo "Erro: Dispositivo $DEVICE não encontrado ou não é um dispositivo de caractere."
    echo "Dica: Verifique se o conversor USB-Serial está conectado."
    exit 1
fi

# Verifica permissão de leitura e escrita no dispositivo
if [ ! -r "$DEVICE" ] || [ ! -w "$DEVICE" ]; then
    echo "Erro: Sem permissão de leitura/escrita em $DEVICE."
    echo "Dica: Tente executar com sudo ou adicione seu usuário ao grupo de acesso serial:"
    if [ -f /etc/arch-release ]; then
        echo "  sudo usermod -aG uucp \$USER"
    else
        echo "  sudo usermod -aG dialout \$USER"
    fi
    echo "Nota: Após se adicionar ao grupo, você precisará fazer logout e login novamente para aplicar as alterações."
    exit 1
fi

# Mata qualquer processo que esteja usando o dispositivo (como outra instância do picocom)
if command -v fuser >/dev/null 2>&1; then
    if fuser "$DEVICE" >/dev/null 2>&1; then
        echo "Limpando sessões anteriores em $DEVICE usando fuser..."
        fuser -k -TERM "$DEVICE" >/dev/null 2>&1
        sleep 0.5
        if fuser "$DEVICE" >/dev/null 2>&1; then
            fuser -k -KILL "$DEVICE" >/dev/null 2>&1
            sleep 0.5
        fi
    fi
elif command -v lsof >/dev/null 2>&1; then
    PIDS=$(lsof -t "$DEVICE" 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "Limpando sessões anteriores em $DEVICE usando lsof..."
        for PID in $PIDS; do
            kill -TERM "$PID" 2>/dev/null
        done
        sleep 0.5
        for PID in $PIDS; do
            if kill -0 "$PID" 2>/dev/null; then
                kill -KILL "$PID" 2>/dev/null
            fi
        done
    fi
fi

echo "Conectando a $DEVICE ($BAUD bps)..."
echo "Comandos picocom úteis:"
echo "  Ctrl+A Ctrl+X -> Sair"
echo "  Ctrl+A Ctrl+U -> Aumentar baudrate"
echo "  Ctrl+A Ctrl+D -> Diminuir baudrate"
echo ""

# Ajusta a largura da linha no terminal se for menor que 200 colunas (útil para saídas longas de log)
# Para evitar corromper a largura do terminal após a saída do script, salvamos a largura original e a restauramos ao sair.
if [ -t 0 ]; then
    ORIG_COLS=$(tput cols 2>/dev/null || stty size 2>/dev/null | cut -d' ' -f2)
    if [ -n "$ORIG_COLS" ]; then
        trap 'stty cols "$ORIG_COLS" 2>/dev/null' EXIT INT TERM
        if [ "$ORIG_COLS" -lt 200 ]; then
            stty cols 200 2>/dev/null
        fi
    fi
fi

# picocom flags:
# -b: baudrate
# --imap lfcrlf: converte LF vindo do dispositivo para CR+LF (corrige o "efeito escadinha")
# --flow n: sem controle de fluxo
picocom -b "$BAUD" "$DEVICE" --imap lfcrlf --flow n
