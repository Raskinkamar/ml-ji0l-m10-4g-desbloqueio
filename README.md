# Desbloqueio do tablet ML-JI0L M10 4G

Guia em português para remover e bloquear o Google Device Setup/OobConfig no
tablet `M10_4G`, variante `ML_JI0L_M10_4G`, plataforma MediaTek
MT6765/MT8768t.

Há dois métodos complementares:

1. **Remoção pelo Preloader/BROM:** retira o APK de `product_a` antes de iniciar
   o Android. É o método principal e sobrevive a reinícios e restaurações de
   fábrica.
2. **Bloqueio pelo ADB:** quando o Android já está inicializado, bloqueia a
   Activity de reset, restringe a execução em segundo plano e desativa o pacote
   para o usuário principal. É útil se uma atualização restaurar o aplicativo.

> Use somente em um tablet seu ou em equipamento que você tenha autorização
> para reparar. Faça backup antes de gravar partições. Um preloader, layout ou
> `vbmeta` incompatível pode impedir o aparelho de iniciar.

## O que é bloqueado

Pacote:

```text
com.google.android.apps.work.oobconfig
```

Activity de reset/zero-touch:

```text
com.google.android.apps.work.oobconfig/.zerotouch.FactoryResetActivity
```

No firmware testado, o APK estava somente em:

```text
product_a:/priv-app/OobConfig/
```

Não foi encontrada outra cópia em `system_a`.

## Arquivos e ferramentas necessários

- Linux com Python 3, `libusb` e FUSE;
- [mtkclient](https://github.com/bkerler/mtkclient);
- Android platform-tools (`adb`);
- `lpdump`, `lpunpack`, `lpmake`, `fuse2fs` e `apkanalyzer`;
- preloader correto da variante, usado apenas para inicializar a DRAM;
- backups verificados de `super`, `vbmeta_a` e partições críticas.

O preloader usado no teste tinha este SHA-256:

```text
ca8c09a3b283289779be321eb11a25d601154786a7cc33757ea5a4ef541f8e6d
```

Esse hash é apenas uma referência do aparelho testado. Não grave o preloader no
tablet durante este procedimento. Passe-o somente ao mtkclient com
`--preloader=/caminho/preloader.bin` para configurar a DRAM.

## Layout testado

A GPT possuía uma partição física `super` de 4 GiB. Os metadados do slot 0 eram:

| Partição lógica | Primeiro setor em `super` | Offset em bytes | Tamanho |
| --- | ---: | ---: | ---: |
| `product_a` | 2.048 | 1.048.576 | 1.218.813.952 bytes |
| `vendor_a` | 2.383.872 | 1.220.542.464 | 186.642.432 bytes |
| `system_a` | 2.748.416 | 1.407.188.992 | 1.263.587.328 bytes |

Confira sempre com `lpdump`. Não reutilize esses offsets em outra imagem ou
variante sem validar o layout.

---

## Método 1 — remover pelo Preloader/BROM

Embora muita gente chame esta etapa de “bootloader”, o acesso usado aqui é o
MediaTek Preloader/BROM com um Download Agent do mtkclient.

### 1. Verificar os backups

```bash
sha256sum /caminho/preloader.bin \
          /caminho/super_full.bin \
          /caminho/vbmeta_a.bin

lpdump /caminho/super_full.bin
```

Confirme o chipset, a origem das imagens, os nomes, tamanhos e extents das
partições lógicas.

### 2. Conectar e ler a GPT

Execute dentro do checkout do mtkclient:

```bash
python3 mtk.py printgpt \
  --preloader=/caminho/preloader.bin
```

Desligue o tablet e conecte o USB segurando Volume+ e Volume−. No teste, a
sequência válida exibiu `DRAM setup passed` antes da GPT. Pare se o hardware ou
layout detectado for diferente.

### 3. Preparar uma cópia de `super`

```bash
cp --reflink=auto super_full.bin super_sem_oobconfig.bin
mkdir -p mnt_product
lpdump super_sem_oobconfig.bin
```

Somente para o layout testado, monte `product_a` no offset 1.048.576:

```bash
fuse2fs super_sem_oobconfig.bin mnt_product \
  -o rw,fakeroot,offset=1048576
```

Confirme o nome interno do APK antes de remover:

```bash
apkanalyzer manifest application-id \
  mnt_product/priv-app/OobConfig/OobConfig.apk
```

O resultado esperado é:

```text
com.google.android.apps.work.oobconfig
```

Remova apenas o diretório confirmado:

```bash
rm -rf -- mnt_product/priv-app/OobConfig
sync
fusermount3 -u mnt_product
```

Monte novamente como somente leitura e confirme que não existe `OobConfig`.
Execute `lpdump` outra vez para verificar que os metadados de `super` continuam
intactos.

### 4. Preparar `vbmeta_a`

A alteração de `product_a` invalida o hash do Android Verified Boot. Em aparelho
com desbloqueio autorizado, prepare uma cópia compatível de `vbmeta_a` com as
flags `3` (desativar verity e verification):

```bash
python3 scripts/preparar_vbmeta.py \
  /caminho/vbmeta_a.bin vbmeta_a_flags3.bin
```

O script recusa imagens sem o cabeçalho `AVB0`, flags inesperadas e alteração do
arquivo de origem. Ele não desbloqueia um bootloader bloqueado.

### 5. Gravar e limpar os dados

Os comandos abaixo sobrescrevem partições. Não desconecte o USB durante a
gravação:

```bash
python3 mtk.py w super /caminho/super_sem_oobconfig.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py w vbmeta_a /caminho/vbmeta_a_flags3.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py e userdata,metadata \
  --preloader=/caminho/preloader.bin
```

O aparelho testado usava o slot `_a`. Confirme o slot do seu aparelho. Não
apague `system_a`: ele é uma partição lógica dentro de `super`.

### 6. Verificar após iniciar

Ative a depuração USB, autorize o computador e execute:

```bash
./scripts/verificar_desbloqueio.sh
```

O resultado esperado é:

- `boot_completed=1`;
- `oobconfig=ausente`;
- `factory_reset_activity=ausente`;
- Play Store, Play Services, GSF e Setup Wizard presentes.

---

## Método 2 — bloquear com o Android inicializado

Use este método quando o pacote ainda estiver instalado ou se uma OTA/regravação
o restaurar. Ele faz, nesta ordem:

1. bloqueia `FactoryResetActivity`;
2. nega wake lock e execução em segundo plano;
3. nega início em primeiro plano e configurações restritas, quando suportados;
4. desativa todo o pacote para o usuário 0.

Com a depuração USB autorizada:

```bash
./scripts/bloquear_oobconfig_adb.sh
```

Os comandos principais são:

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

Se o APK já foi removido pelo Método 1, o script informa que o pacote está
ausente e não altera nada.

## Proteção após atualizações

Reiniciar, desligar ou restaurar os dados de fábrica não recria o APK removido de
`product_a`. Uma OTA ou regravação completa pode substituir `product_a`.

Para desativar a aplicação automática de OTA em builds que respeitam a opção:

```bash
adb shell settings put global ota_disable_automatic_update 1
```

Isso não impede uma atualização iniciada manualmente. Depois de qualquer
atualização, execute novamente:

```bash
./scripts/bloquear_oobconfig_adb.sh
./scripts/verificar_desbloqueio.sh
```

## Recuperação

Se o Android não iniciar, volte ao BROM usando o preloader compatível apenas como
dado de DRAM e restaure os backups originais de `super` e `vbmeta_a`.

Não experimente com `preloader`, `nvram`, `nvdata`, `persist`, `proinfo`, RPMB ou
OTP. Essas regiões podem conter calibração e dados de segurança exclusivos do
aparelho.

