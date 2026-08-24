# Desbloqueio do ML-JI0L M10 4G

Remoção e bloqueio do Google Device Setup/OobConfig no tablet:

- modelo: `M10_4G`;
- variante: `ML_JI0L_M10_4G`;
- plataforma: MediaTek MT6765/MT8768t;
- pacote: `com.google.android.apps.work.oobconfig`;
- localização: `product_a:/priv-app/OobConfig/`.

O procedimento foi testado somente nessa variante e nesse layout. Use apenas em
aparelho próprio ou com autorização de manutenção.

## Uso pelo assistente

```bash
git clone https://github.com/Raskinkamar/ml-ji0l-m10-4g-desbloqueio.git
cd ml-ji0l-m10-4g-desbloqueio
./desbloquear_m10.sh
```

O menu permite:

1. preparar `super` e remover OobConfig;
2. preparar `vbmeta_a`;
3. gravar as imagens e limpar os dados;
4. bloquear OobConfig pelo ADB;
5. verificar o resultado;
6. desativar a aplicação automática de OTA.

## Requisitos

- Linux com Python 3, `libusb` e FUSE;
- [mtkclient](https://github.com/bkerler/mtkclient);
- Android platform-tools (`adb`);
- `lpdump`, `lpunpack`, `lpmake`, `fuse2fs` e `apkanalyzer`;
- preloader correto da variante;
- backups de `super`, `vbmeta_a` e partições críticas.

SHA-256 do preloader usado no teste:

```text
ca8c09a3b283289779be321eb11a25d601154786a7cc33757ea5a4ef541f8e6d
```

O preloader é usado somente para configurar a DRAM por meio do parâmetro
`--preloader`. **Não grave o preloader no tablet.**

## Métodos

### Remoção persistente via Preloader/BROM

Remove o APK de `product_a` e grava novamente a partição `super`. A remoção
permanece após reinicialização e restauração de fábrica. Uma OTA ou regravação de
firmware pode restaurar o pacote.

### Bloqueio complementar via ADB

Se o pacote estiver instalado, o script desativa a Activity relacionada ao
zero-touch, aplica restrições de execução e desativa o pacote para o usuário 0:

```bash
./scripts/bloquear_oobconfig_adb.sh
```

Para verificar o estado:

```bash
./scripts/verificar_desbloqueio.sh
```

## `vbmeta_a`

O procedimento testado alterou `vbmeta_a` com flags `3` como medida de
compatibilidade após a modificação de `product_a`.

Não foi feito um teste comparativo usando `product_a` modificada com o
`vbmeta_a` original. Portanto, não é possível afirmar que essa alteração seja
obrigatória em todas as unidades.

## Procedimento manual

<details>
<summary>Mostrar comandos</summary>

### 1. Conferir as imagens

```bash
sha256sum /caminho/preloader.bin \
          /caminho/super_full.bin \
          /caminho/vbmeta_a.bin

lpdump /caminho/super_full.bin
```

Layout observado no aparelho testado:

| Partição lógica | Primeiro setor | Offset | Tamanho |
| --- | ---: | ---: | ---: |
| `product_a` | 2.048 | 1.048.576 | 1.218.813.952 bytes |
| `vendor_a` | 2.383.872 | 1.220.542.464 | 186.642.432 bytes |
| `system_a` | 2.748.416 | 1.407.188.992 | 1.263.587.328 bytes |

Não reutilize esses valores sem conferir o resultado de `lpdump`.

### 2. Ler a GPT

Dentro do checkout do mtkclient:

```bash
python3 mtk.py printgpt \
  --preloader=/caminho/preloader.bin
```

Com o tablet desligado, conecte o USB segurando Volume+ e Volume−. No aparelho
testado, a conexão correta exibiu `DRAM setup passed`.

### 3. Remover OobConfig de `product_a`

```bash
cp --reflink=auto super_full.bin super_sem_oobconfig.bin
mkdir -p mnt_product
lpdump super_sem_oobconfig.bin

fuse2fs super_sem_oobconfig.bin mnt_product \
  -o rw,fakeroot,offset=1048576
```

Confirme o pacote antes de remover:

```bash
apkanalyzer manifest application-id \
  mnt_product/priv-app/OobConfig/OobConfig.apk
```

Resultado esperado:

```text
com.google.android.apps.work.oobconfig
```

Remova e desmonte:

```bash
rm -rf -- mnt_product/priv-app/OobConfig
sync
fusermount3 -u mnt_product
```

### 4. Preparar `vbmeta_a`

```bash
python3 scripts/preparar_vbmeta.py \
  /caminho/vbmeta_a.bin vbmeta_a_flags3.bin
```

### 5. Gravar e limpar os dados

```bash
python3 mtk.py w super /caminho/super_sem_oobconfig.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py w vbmeta_a /caminho/vbmeta_a_flags3.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py e userdata,metadata \
  --preloader=/caminho/preloader.bin
```

O aparelho testado usava o slot `_a`. Não apague `system_a`: ela é uma partição
lógica dentro de `super`.

### 6. Bloquear pelo ADB

```bash
adb shell pm disable-user --user 0 \
  com.google.android.apps.work.oobconfig/.zerotouch.FactoryResetActivity

adb shell cmd appops set com.google.android.apps.work.oobconfig WAKE_LOCK deny
adb shell cmd appops set com.google.android.apps.work.oobconfig RUN_IN_BACKGROUND deny
adb shell cmd appops set com.google.android.apps.work.oobconfig RUN_ANY_IN_BACKGROUND deny
adb shell cmd appops set com.google.android.apps.work.oobconfig START_FOREGROUND deny
adb shell cmd appops set com.google.android.apps.work.oobconfig ACCESS_RESTRICTED_SETTINGS deny

adb shell pm disable-user --user 0 \
  com.google.android.apps.work.oobconfig
```

### 7. Desativar aplicação automática de OTA

```bash
adb shell settings put global ota_disable_automatic_update 1
```

Essa opção não impede uma atualização iniciada manualmente.

</details>

## Limitações e cuidados

- Faça backup antes de gravar qualquer partição.
- Não use imagens, offsets ou preloaders de outra variante.
- Não há confirmação de compatibilidade com outros dispositivos MT6765/MT8768t.
- Não desconecte o USB durante a gravação.
- A alteração de `vbmeta_a` não desbloqueia um bootloader bloqueado.

## Recuperação

Se o Android não iniciar, volte ao BROM usando o preloader correto somente como
dado de configuração da DRAM e restaure os backups originais de `super` e
`vbmeta_a`.

Não altere `preloader`, `nvram`, `nvdata`, `persist`, `proinfo`, RPMB ou OTP sem
saber exatamente o que está fazendo. Essas regiões podem conter dados exclusivos
do aparelho.
