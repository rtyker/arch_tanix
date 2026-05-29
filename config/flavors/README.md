# Flavors

Cada flavor é um conjunto de arquivos consumidos por `scripts/lib/apply-flavor.sh`
ao montar a imagem (`FLAVOR=<nome> ./scripts/04-build-image*.sh`). Os pacotes são
instalados na **própria box no 1º boot** (serviço `tx9-firstboot`), não no host.

## Arquivos por flavor `<nome>`

| Arquivo              | Obrigatório | Conteúdo |
|----------------------|-------------|----------|
| `<nome>.pkgs`        | sim         | pacotes (1 por linha; `#` comenta; comentário inline permitido) |
| `<nome>.enable`      | não         | unidades systemd a habilitar no 1º boot (1 por linha) |
| `<nome>.target`      | não         | default target (ex.: `graphical.target`) |
| `<nome>.files/`      | não         | árvore copiada para a raiz do rootfs (ex.: `etc/greetd/config.toml`) |
| `<nome>.bootargs`    | não         | params EXTRA de kernel cmdline, anexados ao `bootargs` base no `uEnv.ini` (1 token/linha; `#` comenta) |
| `<nome>.nofirstboot` | não         | só a presença importa: pula o serviço `tx9-firstboot` **e** todo o setup de rede (flavor 100% offline) |

`base.pkgs` e `base.enable` são **sempre** mesclados ao flavor escolhido, então
cada `<nome>.pkgs` lista só o que é específico dele.

## `failsafe` — diagnóstico de boot

O flavor `failsafe` é o **mínimo absoluto**: `failsafe.pkgs` vazio + `failsafe.nofirstboot`
(sem pacman, sem rede) + `failsafe.files/` com autologin root no serial (`ttyAML0`)
e no HDMI (`tty1`) e `default.target` forçado em `multi-user.target`. O
`failsafe.bootargs` liga log máximo desde o início (`earlycon`, `keep_bootcon`,
`ignore_loglevel`, `initcall_debug`, …). Serve para responder: *o kernel chega a
montar o rootfs e rodar o init?* Se nem isto cair num shell, o problema é
kernel/early boot — capture o serial (`earlycon` já imprime antes do tty subir).

## Criar um novo flavor

1. `cp video.pkgs meu.pkgs` e edite a lista.
2. (opcional) crie `meu.enable`, `meu.target`, `meu.files/`.
3. `FLAVOR=meu ./scripts/04-build-image-rootless.sh`.
