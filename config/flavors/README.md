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

`base.pkgs` e `base.enable` são **sempre** mesclados ao flavor escolhido, então
cada `<nome>.pkgs` lista só o que é específico dele.

## Criar um novo flavor

1. `cp video.pkgs meu.pkgs` e edite a lista.
2. (opcional) crie `meu.enable`, `meu.target`, `meu.files/`.
3. `FLAVOR=meu ./scripts/04-build-image-rootless.sh`.
