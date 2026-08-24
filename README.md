# Desbloqueio do tablet ML-JI0L M10 4G

Este repositório reúne o que fiz para recuperar um tablet `M10_4G`, variante
`ML_JI0L_M10_4G`, com plataforma MediaTek MT6765/MT8768t, que estava preso ao
processo de provisionamento MDM/Zero-touch.

A solução principal foi remover o OobConfig de `product_a` pelo modo
Preloader/BROM. Também deixei um bloqueio complementar por ADB para o caso de o
pacote voltar depois de uma atualização ou regravação.

O procedimento foi testado nessa unidade e nesse layout. Use somente em aparelho
próprio ou que você tenha autorização para reparar.

## Contexto

Minha primeira ideia foi a mais óbvia: encontrar uma ROM compatível e fazer o
flash completo do tablet. O problema é que não encontrei uma imagem confiável
para essa variante específica.

Em vez de substituir o sistema inteiro por uma ROM de origem incerta, continuei
a investigação usando o firmware disponível no próprio aparelho. Ao analisar as
partições dinâmicas, encontrei o OobConfig dentro de `product_a` e confirmei o
nome do pacote pelo manifesto do APK.

A partir daí, decidi modificar somente o componente envolvido no provisionamento,
mantendo o restante do firmware. Depois transformei os comandos usados durante a
investigação em scripts para não precisar repetir tudo manualmente.

## O que foi encontrado

Dispositivo testado:

- modelo: `M10_4G`;
- variante: `ML_JI0L_M10_4G`;
- plataforma: MediaTek MT6765/MT8768t;
- armazenamento com partições dinâmicas dentro de `super`;
- slot usado no teste: `_a`.

O pacote identificado foi:

```text
com.google.android.apps.work.oobconfig
```

O APK estava em:

```text
product_a:/priv-app/OobConfig/
```

Não encontrei outra cópia em `system_a`.

Também foi identificada esta Activity relacionada ao fluxo de
configuração/zero-touch:

```text
com.google.android.apps.work.oobconfig/.zerotouch.FactoryResetActivity
```

O OobConfig não é descrito aqui como sendo o próprio MDM. Ele é o componente de
configuração/provisionamento que apareceu durante a investigação e que foi
removido no procedimento testado.

### Layout observado

A GPT tinha uma partição física `super` de 4 GiB. Os metadados do slot 0 eram:

| Partição lógica | Primeiro setor em `super` | Offset em bytes | Tamanho |
| --- | ---: | ---: | ---: |
| `product_a` | 2.048 | 1.048.576 | 1.218.813.952 bytes |
| `vendor_a` | 2.383.872 | 1.220.542.464 | 186.642.432 bytes |
| `system_a` | 2.748.416 | 1.407.188.992 | 1.263.587.328 bytes |

Esses valores são específicos da imagem analisada. Confira o seu arquivo com
`lpdump` antes de usar qualquer offset.

## Estratégia utilizada

### 1. Modificação via Preloader/BROM

O acesso foi feito pelo MediaTek Preloader/BROM com o Download Agent do
mtkclient. Embora às vezes essa etapa seja chamada informalmente de “bootloader”,
ela acontece antes do bootloader Android.

O procedimento usa uma cópia da partição `super`, monta a região correspondente
a `product_a`, confirma o pacote e remove apenas o diretório do OobConfig. Depois,
a imagem modificada é gravada novamente no tablet.

Essa é a alteração principal. Como o APK deixa de existir em `product_a`, ele não
volta apenas porque o tablet foi reiniciado ou restaurado para os padrões de
fábrica.

### 2. Bloqueio complementar via ADB

O segundo método existe como proteção posterior. Se o pacote ainda estiver
instalado ou for restaurado por uma OTA/regravação, o script:

1. desativa `FactoryResetActivity`;
2. restringe wake lock e execução em segundo plano;
3. restringe início em primeiro plano e configurações restritas, quando essas
   operações são aceitas pela versão do Android;
4. desativa o pacote para o usuário 0.

Quando o APK já foi removido pelo primeiro método, o script apenas informa que o
pacote não está presente.

## Android Verified Boot e `vbmeta`

Remover o APK altera o conteúdo de `product_a`. Como essa partição participa da
cadeia do Android Verified Boot, existe a possibilidade de o AVB rejeitar a
imagem modificada durante a inicialização.

Neste procedimento, o `vbmeta_a` foi alterado com flags `3` como medida de
compatibilidade. Não foi realizado um teste comparativo mantendo o vbmeta
original, portanto não é possível afirmar que essa etapa seja obrigatória para
todas as unidades.

O que foi confirmado é que o tablet iniciou com a combinação usada no teste:
`product_a` sem OobConfig e `vbmeta_a` com flags `3`.

## Requisitos

- Linux com Python 3, `libusb` e FUSE;
- [mtkclient](https://github.com/bkerler/mtkclient);
- Android platform-tools (`adb`);
- `lpdump`, `lpunpack`, `lpmake`, `fuse2fs` e `apkanalyzer`;
- preloader correto da variante, usado apenas para configurar a DRAM;
- backups de `super`, `vbmeta_a` e das partições críticas.

O preloader usado no teste tinha este SHA-256:

```text
ca8c09a3b283289779be321eb11a25d601154786a7cc33757ea5a4ef541f8e6d
```

Esse hash é apenas uma referência da unidade testada. O preloader não foi
gravado no tablet: ele foi passado ao mtkclient com
`--preloader=/caminho/preloader.bin` somente para a configuração da DRAM.

## Procedimento

### Usando o assistente

Para usar o menu interativo:

```bash
git clone https://github.com/Raskinkamar/ml-ji0l-m10-4g-desbloqueio.git
cd ml-ji0l-m10-4g-desbloqueio
./desbloquear_m10.sh
```

O menu reúne a preparação de `super`, a preparação de `vbmeta_a`, a gravação, o
bloqueio por ADB e a verificação final.

As etapas manuais usadas na investigação estão abaixo.

### 1. Conferir os arquivos

```bash
sha256sum /caminho/preloader.bin \
          /caminho/super_full.bin \
          /caminho/vbmeta_a.bin

lpdump /caminho/super_full.bin
```

Confira o chipset, a origem das imagens, os nomes, tamanhos e extents das
partições lógicas.

### 2. Conectar pelo BROM e ler a GPT

Dentro do checkout do mtkclient:

```bash
python3 mtk.py printgpt \
  --preloader=/caminho/preloader.bin
```

Com o tablet desligado, conecte o USB segurando Volume+ e Volume−. Na unidade
testada, a conexão correta exibiu `DRAM setup passed` antes da GPT. Interrompa se
o hardware ou o layout detectado for diferente.

### 3. Preparar a imagem `super`

Trabalhe em uma cópia:

```bash
cp --reflink=auto super_full.bin super_sem_oobconfig.bin
mkdir -p mnt_product
lpdump super_sem_oobconfig.bin
```

No layout testado, `product_a` começa no offset 1.048.576:

```bash
fuse2fs super_sem_oobconfig.bin mnt_product \
  -o rw,fakeroot,offset=1048576
```

Antes de remover qualquer coisa, confirme o pacote do APK:

```bash
apkanalyzer manifest application-id \
  mnt_product/priv-app/OobConfig/OobConfig.apk
```

Resultado esperado:

```text
com.google.android.apps.work.oobconfig
```

Remova o diretório confirmado, sincronize e desmonte:

```bash
rm -rf -- mnt_product/priv-app/OobConfig
sync
fusermount3 -u mnt_product
```

Depois, monte o mesmo offset como somente leitura e confira se não restou uma
cópia de `OobConfig`. Execute também `lpdump` novamente para conferir os
metadados de `super`.

### 4. Preparar `vbmeta_a`

Esta foi a etapa usada no teste, com a ressalva explicada na seção sobre AVB:

```bash
python3 scripts/preparar_vbmeta.py \
  /caminho/vbmeta_a.bin vbmeta_a_flags3.bin
```

O script exige o cabeçalho `AVB0`, recusa flags inesperadas e cria outro arquivo
em vez de alterar a imagem de origem. Ele não desbloqueia um bootloader
bloqueado.

### 5. Gravar e limpar os dados

Os comandos abaixo sobrescrevem partições. Não desconecte o cabo durante a
gravação:

```bash
python3 mtk.py w super /caminho/super_sem_oobconfig.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py w vbmeta_a /caminho/vbmeta_a_flags3.bin \
  --preloader=/caminho/preloader.bin

python3 mtk.py e userdata,metadata \
  --preloader=/caminho/preloader.bin
```

O tablet testado usava o slot `_a`. Confirme o slot antes de gravar. Não apague
`system_a`: ela é uma partição lógica dentro de `super`.

### 6. Verificar depois do primeiro boot

Ative a depuração USB, autorize o computador e execute:

```bash
./scripts/verificar_desbloqueio.sh
```

Na unidade testada, o resultado foi:

- `boot_completed=1`;
- `oobconfig=ausente`;
- `factory_reset_activity=ausente`;
- Play Store, Play Services, GSF e Setup Wizard presentes.

### 7. Aplicar o bloqueio complementar por ADB

Para executar todos os bloqueios pelo script:

```bash
./scripts/bloquear_oobconfig_adb.sh
```

Os comandos reunidos pelo script são:

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

### Atualizações OTA

Uma OTA ou regravação completa pode substituir `product_a` e trazer o pacote de
volta. Para desativar a aplicação automática de OTA em versões que respeitam
essa opção:

```bash
adb shell settings put global ota_disable_automatic_update 1
```

Isso não impede uma atualização iniciada manualmente. Depois de atualizar,
execute novamente:

```bash
./scripts/bloquear_oobconfig_adb.sh
./scripts/verificar_desbloqueio.sh
```

## Limitações e cuidados

- O procedimento foi testado somente na variante `ML_JI0L_M10_4G` e no layout
  descrito neste README.
- Não assuma compatibilidade com outro M10, outra variante ou outro dispositivo
  MT6765/MT8768t.
- Não reutilize offsets, preloaders ou imagens sem conferir a unidade e o
  firmware.
- Faça backup antes de gravar `super`, `vbmeta_a`, `userdata` ou `metadata`.
- A necessidade isolada das flags `3` em `vbmeta_a` não foi testada com um grupo
  de comparação usando o vbmeta original.
- Use apenas em dispositivos próprios ou com autorização de manutenção.

## Recuperação

Se o Android não iniciar, volte ao BROM usando o preloader compatível apenas como
dado de configuração da DRAM e restaure os backups originais de `super` e
`vbmeta_a`.

Não experimente com `preloader`, `nvram`, `nvdata`, `persist`, `proinfo`, RPMB ou
OTP. Essas regiões podem conter calibração e dados de segurança específicos do
aparelho.
