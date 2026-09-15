# BuscaPreço

Totem de consulta de preços para loja física. O cliente passa o produto no
leitor de código de barras e o preço aparece em tela cheia; fora de uso, a tela
fica rodando um carrossel de banners promocionais. Opcionalmente imprime
etiqueta de gôndola numa mini impressora térmica Bluetooth.

Os dados vêm direto de um servidor **Firebird 5** pela rede (fbclient/TCP) — o
app não tem backend próprio.

## Requisitos

- Flutter (Dart SDK `^3.11.4`)
- Um servidor Firebird 5 acessível na rede, com as tabelas `TB_PRODUTO`,
  `TB_PROD_CODIGO_BARRAS`, `TB_PROMOCAO`, `TB_PROMOCAO_ENCARTE` e
  `TB_PRODUTO_PROMOCAO`
- Android (plataforma alvo; as libs `fbclient` nativas já estão em
  `android/app/src/main/jniLibs/`)

## Rodando

```bash
flutter pub get
flutter run
```

Na primeira execução, abra **Configurações** (ícone de engrenagem no canto
superior direito) e informe IP, porta, caminho do `.FDB` e credenciais do
Firebird.

## Build de release

O APK de release precisa de uma keystore própria. Copie
`android/key.properties.example` para `android/key.properties` e preencha:

```bash
keytool -genkey -v -keystore buscapreco.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias buscapreco
flutter build apk --release
```

Sem o `key.properties`, o build ainda funciona mas é assinado com a chave de
**debug** e não serve para distribuição — o Gradle emite um aviso nesse caso.
O `key.properties` e os arquivos `.jks` estão no `.gitignore` e nunca devem ser
versionados.

## Estrutura

| Caminho | O que é |
| --- | --- |
| `lib/screens/home_screen.dart` | Tela do totem: espera, leitura e exibição do produto |
| `lib/screens/settings_screen.dart` | Configuração de banco, banners, cores e impressora |
| `lib/screens/gondola_label_editor_screen.dart` | Editor visual do layout da etiqueta |
| `lib/db/firebird_service.dart` | Consultas ao Firebird |
| `lib/services/gondola_label_service.dart` | Geração da etiqueta (ESC/POS, TSPL e PDF) |
| `lib/services/bluetooth_printer_service.dart` | Envio para a impressora Bluetooth (SPP) |
| `lib/services/banner_storage.dart` | Guarda os banners no armazenamento do app |

## Leitura do produto

Em **Configurações → Leitura do produto** se escolhe por qual campo do cadastro
o texto lido é procurado: **código de barras** (padrão), **código** interno ou
**referência**. A busca é exclusiva, num campo só — procurar nos três ao mesmo
tempo fazia o totem exibir produto trocado, porque o código de barras de um item
pode ser o código interno ou a referência de outro.

A leitura em si chega por duas formas, simultâneas:

- **Leitor físico USB/Bluetooth** que se comporta como teclado — é o modo
  principal do totem. A tela segura o foco do teclado num `Focus` invisível e
  monta o código em [`BarcodeKeyboard`](lib/services/barcode_keyboard.dart) até
  o Enter.

  Não troque isso por um `TextField`: um campo de linha única chama
  `focusNode.unfocus()` logo depois do `onSubmitted`. Como o leitor digita cerca
  de um caractere por milissegundo, os primeiros caracteres da leitura seguinte
  se perdem — o código chega truncado e o totem ou não acha nada, ou mostra um
  produto que não corresponde ao que foi lido.
- **Câmera**, pelo ícone de scanner (`mobile_scanner`), para uso manual.

## Impressora de etiqueta

Suporta dois protocolos, selecionáveis em Configurações:

- **ESC/POS** — padrão. É o que a maioria das mini impressoras Bluetooth
  genéricas entende. Usa comandos nativos de texto e código de barras, sem
  depender de imagem, o que é bem mais confiável nesses aparelhos.
- **TSPL** — para impressoras de etiqueta de verdade, com sensor de gap
  (Zjiang, Xprinter, Gainscha). A etiqueta é rasterizada e enviada como bitmap.

A impressora precisa estar **pareada** no Android antes de aparecer na lista —
o app não faz varredura.

## Testes

```bash
flutter test
```

## Observações de ambiente

**Java 17 é obrigatório.** O Android Gradle Plugin 8.x não roda em JDK 8. Se o
`JAVA_HOME` da máquina apontar para um JDK antigo, aponte o Flutter para o 17
sem mexer na variável global:

```bash
flutter config --jdk-dir="C:\Program Files\Java\jdk-17"
```

**OneDrive.** O projeto está numa pasta sincronizada, o que trava arquivos
durante o build (`Flutter failed to delete a directory...` em `build/` e em
`windows/flutter/ephemeral/.plugin_symlinks`). Se esbarrar nisso, pause a
sincronização ou — de preferência — mova o repositório para fora do OneDrive.

**Gradle: "Unable to establish loopback connection".** Não é problema do
projeto. Significa que a JVM não consegue abrir um socket de loopback nesta
máquina — dá para confirmar com qualquer programa Java que chame
`java.nio.channels.Selector.open()`. Normalmente é antivírus/firewall
bloqueando o `java.exe` ou a pilha Winsock corrompida; o caminho usual é
liberar o Java no antivírus ou rodar `netsh winsock reset` como administrador
e reiniciar.
