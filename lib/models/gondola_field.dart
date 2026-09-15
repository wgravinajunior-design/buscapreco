/// Cada bloco de informação que pode aparecer na etiqueta de gôndola. A
/// impressão (ESC/POS ou TSPL) é sequencial de cima para baixo, então a
/// "disposição" que o usuário escolhe é a ordem, o alinhamento, o tamanho e
/// o agrupamento (dois blocos na mesma linha) de cada um — não posições X/Y
/// livres.
enum GondolaFieldType {
  descricao,
  codigoBarras,
  preco,
  codigoInterno,
  data,
  precoPorUnidade,
  precoOriginal,
  percentualDesconto,
  tituloPromocao,
}

extension GondolaFieldTypeLabel on GondolaFieldType {
  String get rotulo => switch (this) {
        GondolaFieldType.descricao => 'Nome do produto',
        GondolaFieldType.codigoBarras => 'Código de barras',
        GondolaFieldType.preco => 'Preço',
        GondolaFieldType.codigoInterno => 'Código interno',
        GondolaFieldType.data => 'Data de impressão',
        GondolaFieldType.precoPorUnidade => 'Preço por unidade de medida',
        GondolaFieldType.precoOriginal => 'Preço original (promoção)',
        GondolaFieldType.percentualDesconto => 'Percentual de desconto (promoção)',
        GondolaFieldType.tituloPromocao => 'Selo de promoção (promoção)',
      };

  /// Só faz sentido em produtos com promoção ativa — some sozinho da
  /// etiqueta quando não há desconto, mesmo que marcado como visível.
  bool get somentePromocao =>
      this == GondolaFieldType.precoOriginal ||
      this == GondolaFieldType.percentualDesconto ||
      this == GondolaFieldType.tituloPromocao;

  /// O código de barras precisa da própria linha (desenho gráfico), não dá
  /// para juntar com outro bloco na mesma linha.
  bool get podeCompartilharLinha => this != GondolaFieldType.codigoBarras;
}

enum GondolaFieldAlign { esquerda, centro, direita }

extension GondolaFieldAlignLabel on GondolaFieldAlign {
  String get rotulo => switch (this) {
        GondolaFieldAlign.esquerda => 'Esquerda',
        GondolaFieldAlign.centro => 'Centro',
        GondolaFieldAlign.direita => 'Direita',
      };
}

/// Tamanho da fonte do bloco. Os valores mapeiam para múltiplos do tamanho
/// base de cada tipo de bloco (PDF/preview) e para os níveis discretos de
/// zoom de fonte do ESC/POS (1x, 2x, 3x).
enum GondolaFieldSize { normal, grande, gigante }

extension GondolaFieldSizeLabel on GondolaFieldSize {
  String get rotulo => switch (this) {
        GondolaFieldSize.normal => 'Normal',
        GondolaFieldSize.grande => 'Grande',
        GondolaFieldSize.gigante => 'Gigante',
      };

  double get multiplicador => switch (this) {
        GondolaFieldSize.normal => 1.0,
        GondolaFieldSize.grande => 1.5,
        GondolaFieldSize.gigante => 2.2,
      };

  /// 1, 2 ou 3 — nível de zoom ESC/POS (PosTextSize.size1/2/3).
  int get zoomEscPos => switch (this) {
        GondolaFieldSize.normal => 1,
        GondolaFieldSize.grande => 2,
        GondolaFieldSize.gigante => 3,
      };
}

/// Configuração de um bloco: se aparece, em que ordem (posição na lista),
/// alinhado para qual lado, tamanho da fonte, negrito e se deve ficar na
/// mesma linha do bloco visível anterior.
class GondolaFieldConfig {
  final GondolaFieldType tipo;
  bool visivel;
  GondolaFieldAlign alinhamento;
  bool destaque;
  GondolaFieldSize tamanho;
  bool mesmaLinha;

  GondolaFieldConfig({
    required this.tipo,
    this.visivel = true,
    this.alinhamento = GondolaFieldAlign.centro,
    this.destaque = false,
    this.tamanho = GondolaFieldSize.normal,
    this.mesmaLinha = false,
  });

  GondolaFieldConfig copyWith() => GondolaFieldConfig(
        tipo: tipo,
        visivel: visivel,
        alinhamento: alinhamento,
        destaque: destaque,
        tamanho: tamanho,
        mesmaLinha: mesmaLinha,
      );

  static List<GondolaFieldConfig> padrao() => [
        GondolaFieldConfig(
          tipo: GondolaFieldType.descricao,
          alinhamento: GondolaFieldAlign.centro,
          destaque: true,
        ),
        GondolaFieldConfig(tipo: GondolaFieldType.codigoBarras, alinhamento: GondolaFieldAlign.centro),
        GondolaFieldConfig(
          tipo: GondolaFieldType.tituloPromocao,
          alinhamento: GondolaFieldAlign.centro,
          visivel: false,
        ),
        GondolaFieldConfig(
          tipo: GondolaFieldType.precoOriginal,
          alinhamento: GondolaFieldAlign.centro,
          visivel: false,
        ),
        GondolaFieldConfig(
          tipo: GondolaFieldType.preco,
          alinhamento: GondolaFieldAlign.centro,
          destaque: true,
          tamanho: GondolaFieldSize.grande,
        ),
        GondolaFieldConfig(
          tipo: GondolaFieldType.percentualDesconto,
          alinhamento: GondolaFieldAlign.centro,
          visivel: false,
        ),
        GondolaFieldConfig(tipo: GondolaFieldType.codigoInterno, alinhamento: GondolaFieldAlign.esquerda),
        GondolaFieldConfig(
          tipo: GondolaFieldType.data,
          alinhamento: GondolaFieldAlign.direita,
          mesmaLinha: true,
        ),
        GondolaFieldConfig(tipo: GondolaFieldType.precoPorUnidade, alinhamento: GondolaFieldAlign.esquerda),
      ];

  static List<GondolaFieldConfig> copiarLista(List<GondolaFieldConfig> lista) =>
      lista.map((f) => f.copyWith()).toList();

  static String serializar(List<GondolaFieldConfig> lista) => lista
      .map((f) => '${f.tipo.name}:${f.visivel ? 1 : 0}:${f.alinhamento.name}:${f.destaque ? 1 : 0}:'
          '${f.tamanho.name}:${f.mesmaLinha ? 1 : 0}')
      .join('|');

  static List<GondolaFieldConfig> desserializar(String? texto) {
    if (texto == null || texto.trim().isEmpty) return padrao();
    try {
      final campos = texto.split('|').map((parte) {
        final p = parte.split(':');
        return GondolaFieldConfig(
          tipo: GondolaFieldType.values.byName(p[0]),
          visivel: p[1] == '1',
          alinhamento: GondolaFieldAlign.values.byName(p[2]),
          destaque: p[3] == '1',
          tamanho: p.length > 4 ? GondolaFieldSize.values.byName(p[4]) : GondolaFieldSize.normal,
          mesmaLinha: p.length > 5 && p[5] == '1',
        );
      }).toList();
      // Garante que todo tipo existe na lista (ex.: app atualizado com um
      // campo novo que ainda não estava salvo nas preferências antigas).
      for (final tipo in GondolaFieldType.values) {
        if (!campos.any((f) => f.tipo == tipo)) {
          campos.add(GondolaFieldConfig(tipo: tipo, visivel: false));
        }
      }
      return campos;
    } catch (_) {
      return padrao();
    }
  }
}
