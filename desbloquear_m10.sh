#!/usr/bin/env bash
set -euo pipefail

raiz=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
temporario=''
montagem=''

pausar() {
    printf '\nPressione Enter para continuar...'
    read -r _
}

erro() {
    printf 'Erro: %s\n' "$*" >&2
    exit 1
}

exigir_comando() {
    command -v "$1" >/dev/null 2>&1 || erro "comando não encontrado: $1"
}

pedir_arquivo() {
    local mensagem=$1
    local resposta
    printf '%s: ' "$mensagem" >&2
    read -r resposta
    [[ -f $resposta ]] || erro "arquivo não encontrado: $resposta"
    printf '%s' "$resposta"
}

desmontar() {
    if [[ -n $montagem ]] && mountpoint -q "$montagem" 2>/dev/null; then
        fusermount3 -u "$montagem" || true
    fi
    if [[ -n $temporario ]] && [[ -d $temporario ]]; then
        rmdir "$temporario" 2>/dev/null || true
    fi
}

trap desmontar EXIT INT TERM

preparar_super() {
    exigir_comando lpdump
    exigir_comando fuse2fs
    exigir_comando fusermount3
    exigir_comando apkanalyzer
    exigir_comando mountpoint

    local origem saida setor offset tamanho_super identidade
    origem=$(pedir_arquivo 'Imagem super original')
    printf 'Nome da imagem de saída [super_sem_oobconfig.bin]: '
    read -r saida
    saida=${saida:-super_sem_oobconfig.bin}

    [[ ! -e $saida ]] || erro "a saída já existe: $saida"

    tamanho_super=$(stat -c %s "$origem")
    [[ $tamanho_super -eq 4294967296 ]] || \
        erro "a imagem super deveria ter 4294967296 bytes; encontrado: $tamanho_super"

    setor=$(lpdump "$origem" | awk '
        /Name: product_a/ {produto=1; next}
        produto && /linear super/ {print $NF; exit}
    ')
    [[ $setor =~ ^[0-9]+$ ]] || erro 'não foi possível localizar product_a no lpdump'
    [[ $setor -eq 2048 ]] || \
        erro "layout diferente do testado: product_a começa no setor $setor"
    offset=$((setor * 512))

    printf '\nLayout confirmado. product_a: setor %s, offset %s bytes.\n' "$setor" "$offset"
    printf 'Criando cópia de trabalho...\n'
    cp --reflink=auto -- "$origem" "$saida"

    temporario=$(mktemp -d)
    montagem=$temporario
    fuse2fs "$saida" "$montagem" -o rw,fakeroot,offset="$offset"

    local apk="$montagem/priv-app/OobConfig/OobConfig.apk"
    [[ -f $apk ]] || erro 'OobConfig.apk não foi encontrado em product_a'
    identidade=$(apkanalyzer manifest application-id "$apk")
    [[ $identidade == 'com.google.android.apps.work.oobconfig' ]] || \
        erro "pacote inesperado no APK: $identidade"

    printf '\nAPK confirmado: %s\n' "$identidade"
    printf 'Digite REMOVER para excluir OobConfig da cópia: '
    read -r confirmacao
    [[ $confirmacao == 'REMOVER' ]] || erro 'operação cancelada'

    rm -rf -- "$montagem/priv-app/OobConfig"
    sync
    fusermount3 -u "$montagem"
    montagem=''

    fuse2fs "$saida" "$temporario" -o ro,fakeroot,offset="$offset"
    montagem=$temporario
    if find "$montagem" -iname '*oobconfig*' -print -quit | grep -q .; then
        erro 'a verificação ainda encontrou OobConfig'
    fi
    fusermount3 -u "$montagem"
    montagem=''
    rmdir "$temporario"
    temporario=''

    printf '\nImagem preparada com sucesso: %s\n' "$saida"
    sha256sum "$saida"
}

preparar_vbmeta() {
    local origem saida
    origem=$(pedir_arquivo 'Imagem vbmeta_a original')
    printf 'Nome da imagem de saída [vbmeta_a_flags3.bin]: '
    read -r saida
    saida=${saida:-vbmeta_a_flags3.bin}
    python3 "$raiz/scripts/preparar_vbmeta.py" "$origem" "$saida"
}

gravar_tablet() {
    local pasta_mtk preloader super vbmeta
    printf 'Pasta do mtkclient: '
    read -r pasta_mtk
    [[ -f $pasta_mtk/mtk.py ]] || erro "mtk.py não encontrado em: $pasta_mtk"
    preloader=$(pedir_arquivo 'Preloader correto')
    super=$(pedir_arquivo 'Super preparada sem OobConfig')
    vbmeta=$(pedir_arquivo 'vbmeta_a com flags 3')

    [[ $(stat -c %s "$super") -eq 4294967296 ]] || erro 'tamanho inválido da super'
    [[ $(od -An -tx1 -N4 "$vbmeta" | tr -d ' \n') == '41564230' ]] || \
        erro 'vbmeta sem cabeçalho AVB0'
    [[ $(od -An -tu4 --endian=big -j120 -N4 "$vbmeta" | tr -d ' ') -eq 3 ]] || \
        erro 'as flags de vbmeta não são 3'

    printf '\nEsta etapa grava super e vbmeta_a e apaga userdata/metadata.\n'
    printf 'Digite GRAVAR para continuar: '
    read -r confirmacao
    [[ $confirmacao == 'GRAVAR' ]] || erro 'operação cancelada'

    printf '\nConecte o tablet em BROM quando o mtkclient solicitar.\n'
    python3 "$pasta_mtk/mtk.py" w super "$super" --preloader="$preloader"

    printf '\nReconecte o tablet em BROM para gravar vbmeta_a.\n'
    python3 "$pasta_mtk/mtk.py" w vbmeta_a "$vbmeta" --preloader="$preloader"

    printf '\nReconecte o tablet em BROM para apagar os dados.\n'
    python3 "$pasta_mtk/mtk.py" e userdata,metadata --preloader="$preloader"
    printf '\nGravação concluída. Desconecte o USB e ligue o tablet.\n'
}

mostrar_menu() {
    clear 2>/dev/null || true
    printf '%s\n' \
        '====================================================' \
        ' Desbloqueio ML-JI0L M10 4G' \
        '====================================================' \
        '1) Preparar super e remover OobConfig' \
        '2) Preparar vbmeta_a' \
        '3) Gravar imagens e restaurar o tablet' \
        '4) Bloquear OobConfig pelo ADB' \
        '5) Verificar o desbloqueio pelo ADB' \
        '6) Desativar aplicação automática de OTA' \
        '0) Sair' \
        '===================================================='
    printf 'Escolha: '
}

while true; do
    mostrar_menu
    read -r opcao
    case $opcao in
        1) preparar_super; pausar ;;
        2) preparar_vbmeta; pausar ;;
        3) gravar_tablet; pausar ;;
        4) "$raiz/scripts/bloquear_oobconfig_adb.sh"; pausar ;;
        5) "$raiz/scripts/verificar_desbloqueio.sh"; pausar ;;
        6)
            adb shell settings put global ota_disable_automatic_update 1
            printf 'Atualização automática: desativada.\n'
            pausar
            ;;
        0) exit 0 ;;
        *) printf 'Opção inválida.\n'; pausar ;;
    esac
done

