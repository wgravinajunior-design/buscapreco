import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as epu;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../config/app_config.dart';
import '../models/gondola_field.dart';
import '../models/product_price.dart';
import 'bluetooth_printer_service.dart';

/// Faixa segura de DPI para a rasterização — evita valores absurdos caso o
/// usuário configure uma largura de etiqueta ou de impressora fora do normal.
const _kDpiMinimo = 72.0;
const _kDpiMaximo = 300.0;

/// Ponto de corte de luminância (0-255) para decidir se um pixel vira ponto
/// preto na etiqueta térmica (1 bit por pixel, sem tons de cinza).
const _kLimiarPreto = 170;

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yy');

/// Gera e envia para impressão a etiqueta de gôndola de um produto, no
/// modelo padrão de etiqueta de preço de loja: descrição no topo, código de
/// barras e código interno à esquerda, preço em destaque à direita e, quando
/// disponível, o preço por Kg abaixo.
class GondolaLabelService {
  /// Imprime a etiqueta. Quando há uma impressora Bluetooth configurada em
  /// [AppConfig.gondolaPrinterAddress], envia direto para ela sem abrir
  /// diálogo algum. Sem impressora configurada, cai no diálogo de impressão
  /// padrão do sistema (gera um PDF no modelo visual da etiqueta).
  static Future<void> imprimir(ProductPrice product, AppConfig config) async {
    final endereco = config.gondolaPrinterAddress;
    if (endereco != null && endereco.isNotEmpty) {
      if (config.gondolaProtocol == AppConfig.protocoloTspl) {
        final doc = await _build(product, config);
        await _imprimirBluetoothTspl(doc, config, endereco);
      } else {
        await _imprimirBluetoothEscPos(product, config, endereco);
      }
      return;
    }
    final doc = await _build(product, config);
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: 'etiqueta_${product.codigo}',
    );
  }

  /// Impressoras ESC/POS genéricas (a grande maioria das mini impressoras
  /// térmicas Bluetooth) costumam ter suporte capenga — ou nenhum — ao
  /// comando de imagem raster (GS v 0), o que produz etiquetas embaralhadas.
  /// Comandos nativos de texto e código de barras são muito mais confiáveis
  /// nesses aparelhos, então esse é o caminho padrão para ESC/POS.
  static Future<void> _imprimirBluetoothEscPos(ProductPrice product, AppConfig config, String endereco) async {
    final comando = await _comandosEscPos(product, config);
    await BluetoothPrinterService.enviar(endereco, Uint8List.fromList(comando));
  }

  static Future<List<int>> _comandosEscPos(ProductPrice product, AppConfig config) async {
    final profile = await epu.CapabilityProfile.load();
    final papel = config.gondolaPrinterWidthDots >= 500 ? epu.PaperSize.mm80 : epu.PaperSize.mm58;
    final generator = epu.Generator(papel, profile);
    final bytes = <int>[];

    bytes.addAll(generator.reset());
    // CP850 (Multilingual) é a página de código que cobre corretamente os
    // acentos do português (ç, ã, é...) — a maioria das impressoras ESC/POS
    // (inclusive esta) suporta essa tabela nativamente.
    bytes.addAll(generator.setGlobalCodeTable('CP850'));

    final visiveis = config.gondolaFields.where((c) => c.visivel && temConteudo(c, product)).toList();
    for (final grupo in agrupar(visiveis)) {
      bytes.addAll(_comandoEscPosDoGrupo(generator, grupo, product, config));
    }

    bytes.addAll(generator.feed(2));
    return bytes;
  }

  static epu.PosAlign _posAlign(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => epu.PosAlign.left,
        GondolaFieldAlign.centro => epu.PosAlign.center,
        GondolaFieldAlign.direita => epu.PosAlign.right,
      };

  static epu.PosTextSize _posTextSize(int nivel) => switch (nivel) {
        1 => epu.PosTextSize.size1,
        2 => epu.PosTextSize.size2,
        _ => epu.PosTextSize.size3,
      };

  static List<int> _comandoEscPosDoGrupo(
    epu.Generator generator,
    List<GondolaFieldConfig> grupo,
    ProductPrice product,
    AppConfig config,
  ) {
    if (grupo.length == 1) {
      return _comandoEscPosDoCampo(generator, grupo.first, product, config);
    }
    // Dois blocos na mesma linha (ex.: código interno à esquerda, data à
    // direita) viram duas colunas de 6/12 — sem código de barras aqui, que
    // sempre fica sozinho na própria linha por ser um desenho gráfico.
    final colunas = grupo
        .map((campo) => epu.PosColumn(
              text: textoDoCampo(campo, product) ?? '',
              width: 6,
              styles: epu.PosStyles(
                align: _posAlign(campo.alinhamento),
                bold: campo.destaque,
                // Sem isso o tamanho escolhido no editor era ignorado sempre que
                // o bloco dividia a linha com outro.
                height: _posTextSize(campo.tamanho.zoomEscPos),
                width: _posTextSize(campo.tamanho.zoomEscPos),
              ),
            ))
        .toList();
    return generator.row(colunas);
  }

  static List<int> _comandoEscPosDoCampo(
    epu.Generator generator,
    GondolaFieldConfig campo,
    ProductPrice product,
    AppConfig config,
  ) {
    final align = _posAlign(campo.alinhamento);
    if (campo.tipo == GondolaFieldType.codigoBarras) {
      final bytes = <int>[];
      try {
        bytes.addAll(generator.barcode(
          epu.Barcode.code128(product.codigoBarras!.split('')),
          height: 60,
          width: 2,
          align: align,
        ));
      } catch (_) {
        // Alguns caracteres do código podem não ser aceitos pelo gerador de
        // Code128; nesse caso segue só com o número em texto.
      }
      bytes.addAll(generator.text(product.codigoBarras!, styles: epu.PosStyles(align: align)));
      return bytes;
    }

    final texto = textoDoCampo(campo, product);
    if (texto == null) return const [];
    final zoom = _posTextSize(campo.tamanho.zoomEscPos);
    return generator.text(
      texto,
      styles: epu.PosStyles(align: align, bold: campo.destaque, height: zoom, width: zoom),
    );
  }

  /// Texto de cada bloco (independe do protocolo/formato de saída, e é
  /// reaproveitado pelo preview do editor de etiqueta). Retorna null quando
  /// o bloco não tem o que mostrar — produto sem código de barras, sem
  /// preço por unidade cadastrado, ou sem promoção ativa (para os blocos que
  /// só fazem sentido com desconto).
  static String? textoDoCampo(GondolaFieldConfig campo, ProductPrice product) {
    final temDesconto = product.melhorPreco < product.precoVenda;
    switch (campo.tipo) {
      case GondolaFieldType.descricao:
        return product.descricao.toUpperCase();
      case GondolaFieldType.codigoBarras:
        return null; // tratado à parte, é um desenho gráfico
      case GondolaFieldType.preco:
        return _moeda.format(product.melhorPreco);
      case GondolaFieldType.codigoInterno:
        return 'Cód. ${product.codigo}';
      case GondolaFieldType.data:
        return _data.format(DateTime.now());
      case GondolaFieldType.precoPorUnidade:
        // Preço por unidade de medida do produto. Usa o preço EFETIVO: antes
        // este bloco imprimia sempre o preço cheio, contradizendo o preço
        // grande da etiqueta sempre que havia promoção ativa.
        // Unidade vem direto do cadastro do produto (PRD_UN_VENDA), não é
        // configurável — evita etiqueta com unidade errada por esquecimento.
        final unidade = product.unidade.trim();
        if (unidade.isEmpty) return null;
        return 'Preço/$unidade ${_moeda.format(product.melhorPreco)}';
      case GondolaFieldType.precoOriginal:
        if (!temDesconto) return null;
        return _moeda.format(product.precoVenda);
      case GondolaFieldType.percentualDesconto:
        if (!temDesconto) return null;
        return '-${product.percentualDesconto.toStringAsFixed(0)}%';
      case GondolaFieldType.tituloPromocao:
        if (!temDesconto) return null;
        final titulo = product.encarteTitulo;
        return (titulo != null && titulo.isNotEmpty) ? titulo.toUpperCase() : 'PROMOÇÃO';
    }
  }

  static bool temConteudo(GondolaFieldConfig campo, ProductPrice product) {
    if (campo.tipo == GondolaFieldType.codigoBarras) {
      return product.codigoBarras != null && product.codigoBarras!.isNotEmpty;
    }
    return textoDoCampo(campo, product) != null;
  }

  /// Agrupa em linhas: um bloco marcado como "mesma linha" entra no grupo
  /// anterior (no máximo 2 por linha), desde que nenhum dos dois seja
  /// código de barras — que sempre fica sozinho. Também reaproveitado pelo
  /// preview do editor de etiqueta.
  static List<List<GondolaFieldConfig>> agrupar(List<GondolaFieldConfig> campos) {
    final grupos = <List<GondolaFieldConfig>>[];
    for (final campo in campos) {
      final podeJuntar = campo.mesmaLinha &&
          campo.tipo.podeCompartilharLinha &&
          grupos.isNotEmpty &&
          grupos.last.length < 2 &&
          grupos.last.last.tipo.podeCompartilharLinha;
      if (podeJuntar) {
        grupos.last.add(campo);
      } else {
        grupos.add([campo]);
      }
    }
    return grupos;
  }

  static Future<void> _imprimirBluetoothTspl(pw.Document doc, AppConfig config, String endereco) async {
    final pdfBytes = await doc.save();
    // A imagem precisa nascer com a largura exata (em pontos) que a
    // impressora consegue imprimir por linha — se for maior, os bytes de
    // cada linha "vazam" para a linha seguinte e a etiqueta sai embaralhada.
    final dpi = (config.gondolaPrinterWidthDots * 25.4 / config.gondolaWidthMm).clamp(_kDpiMinimo, _kDpiMaximo);
    final raster = await Printing.raster(pdfBytes, dpi: dpi).first;
    final bitmap = _bitmapDoRaster(raster, larguraMaximaPx: config.gondolaPrinterWidthDots);
    final comando = _tsplDoBitmap(bitmap, config);
    await BluetoothPrinterService.enviar(endereco, comando);
  }

  /// Converte a etiqueta rasterizada (RGBA) em bitmap 1 bit por pixel
  /// (preto/branco), formato de entrada do comando BITMAP do TSPL. O caminho
  /// ESC/POS não passa por aqui: ele usa comandos nativos de texto e código
  /// de barras, sem imagem.
  /// [larguraMaximaPx] garante que a imagem nunca saia mais larga do que a
  /// impressora suporta, mesmo com pequenos arredondamentos do rasterizador.
  static _Bitmap _bitmapDoRaster(PdfRaster raster, {required int larguraMaximaPx}) {
    final strideOriginal = raster.width;
    final largura = strideOriginal > larguraMaximaPx ? larguraMaximaPx : strideOriginal;
    final altura = raster.height;
    final larguraBytes = (largura + 7) ~/ 8;
    final dados = Uint8List(larguraBytes * altura);
    final pixels = raster.pixels;

    for (var y = 0; y < altura; y++) {
      for (var x = 0; x < largura; x++) {
        final i = (y * strideOriginal + x) * 4;
        final luminancia = pixels[i] * 0.299 + pixels[i + 1] * 0.587 + pixels[i + 2] * 0.114;
        if (luminancia < _kLimiarPreto) {
          final indiceByte = y * larguraBytes + (x >> 3);
          final bit = 7 - (x & 7);
          dados[indiceByte] |= 1 << bit;
        }
      }
    }
    return _Bitmap(larguraBytes: larguraBytes, altura: altura, dados: dados);
  }

  /// Comandos TSPL — protocolo de impressoras de etiqueta "de verdade" (com
  /// sensor de gap entre etiquetas), como algumas Zjiang/Xprinter/Gainscha.
  ///
  /// Atenção à polaridade: no comando BITMAP do TSPL o bit **0** é que imprime
  /// o ponto preto (1 = branco), ao contrário do raster do ESC/POS. Como
  /// [_bitmapDoRaster] monta o bitmap na convenção intuitiva (bit 1 = tinta),
  /// os bytes são invertidos aqui na saída — sem isso a etiqueta sai em
  /// negativo, com o fundo todo preto.
  static Uint8List _tsplDoBitmap(_Bitmap bitmap, AppConfig config) {
    final cabecalho = 'SIZE ${config.gondolaWidthMm.toStringAsFixed(0)} mm,'
        '${config.gondolaHeightMm.toStringAsFixed(0)} mm\r\n'
        'GAP 2 mm,0 mm\r\n'
        'CLS\r\n'
        'BITMAP 0,0,${bitmap.larguraBytes},${bitmap.altura},0,';
    final rodape = '\r\nPRINT 1,1\r\n';

    final invertido = Uint8List(bitmap.dados.length);
    for (var i = 0; i < bitmap.dados.length; i++) {
      invertido[i] = ~bitmap.dados[i] & 0xFF;
    }

    final builder = BytesBuilder();
    builder.add(cabecalho.codeUnits);
    builder.add(invertido);
    builder.add(rodape.codeUnits);
    return builder.toBytes();
  }

  static Future<pw.Document> _build(ProductPrice product, AppConfig config) async {
    final doc = pw.Document();
    final formato = PdfPageFormat(
      config.gondolaWidthMm * PdfPageFormat.mm,
      config.gondolaHeightMm * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm,
    );

    doc.addPage(
      pw.Page(
        pageFormat: formato,
        build: (context) => _label(product, config),
      ),
    );
    return doc;
  }

  /// Layout vertical, na mesma ordem/alinhamento/tamanho/agrupamento
  /// configurados pelo usuário no editor de etiqueta — mantém o PDF (TSPL e
  /// diálogo do sistema) fiel ao que é gerado para ESC/POS.
  static pw.Widget _label(ProductPrice product, AppConfig config) {
    final visiveis = config.gondolaFields.where((c) => c.visivel && temConteudo(c, product)).toList();
    final linhas = agrupar(visiveis).map((grupo) => _linhaPdfDoGrupo(grupo, product, config)).toList();

    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.75)),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: linhas,
      ),
    );
  }

  static pw.Alignment _pwAlignment(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => pw.Alignment.centerLeft,
        GondolaFieldAlign.centro => pw.Alignment.center,
        GondolaFieldAlign.direita => pw.Alignment.centerRight,
      };

  static pw.TextAlign _pwTextAlign(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => pw.TextAlign.left,
        GondolaFieldAlign.centro => pw.TextAlign.center,
        GondolaFieldAlign.direita => pw.TextAlign.right,
      };

  static double _tamanhoBasePdf(GondolaFieldType tipo) => switch (tipo) {
        GondolaFieldType.descricao => 9,
        GondolaFieldType.codigoBarras => 7,
        GondolaFieldType.preco => 14,
        GondolaFieldType.codigoInterno => 6.5,
        GondolaFieldType.data => 6.5,
        GondolaFieldType.precoPorUnidade => 6.5,
        GondolaFieldType.precoOriginal => 8,
        GondolaFieldType.percentualDesconto => 10,
        GondolaFieldType.tituloPromocao => 8,
      };

  static pw.Widget _linhaPdfDoGrupo(List<GondolaFieldConfig> grupo, ProductPrice product, AppConfig config) {
    if (grupo.length == 1) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: _conteudoPdfDoCampo(grupo.first, product, config),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: grupo.map((c) => pw.Expanded(child: _conteudoPdfDoCampo(c, product, config))).toList(),
      ),
    );
  }

  static pw.Widget _conteudoPdfDoCampo(GondolaFieldConfig campo, ProductPrice product, AppConfig config) {
    if (campo.tipo == GondolaFieldType.codigoBarras) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Align(
            alignment: _pwAlignment(campo.alinhamento),
            child: pw.BarcodeWidget(
              barcode: Barcode.code128(),
              data: product.codigoBarras!,
              width: 90,
              height: 24,
              drawText: false,
            ),
          ),
          pw.Text(
            product.codigoBarras!,
            textAlign: _pwTextAlign(campo.alinhamento),
            style: const pw.TextStyle(fontSize: 7),
          ),
        ],
      );
    }

    final texto = textoDoCampo(campo, product) ?? '';
    return pw.Text(
      texto,
      textAlign: _pwTextAlign(campo.alinhamento),
      maxLines: campo.tipo == GondolaFieldType.descricao ? 2 : null,
      overflow: campo.tipo == GondolaFieldType.descricao ? pw.TextOverflow.clip : null,
      style: pw.TextStyle(
        fontSize: _tamanhoBasePdf(campo.tipo) * campo.tamanho.multiplicador,
        fontWeight: campo.destaque ? pw.FontWeight.bold : pw.FontWeight.normal,
        decoration: campo.tipo == GondolaFieldType.precoOriginal ? pw.TextDecoration.lineThrough : null,
      ),
    );
  }
}

class _Bitmap {
  final int larguraBytes;
  final int altura;
  final Uint8List dados;
  const _Bitmap({required this.larguraBytes, required this.altura, required this.dados});
}
