import 'dart:typed_data';
import 'package:fbdb/fbdb.dart';
import '../config/app_config.dart';
import '../models/product_price.dart';

class FirebirdException implements Exception {
  final String message;
  FirebirdException(this.message);
  @override
  String toString() => message;
}

/// Camada de acesso ao Firebird 5. Conecta direto via rede (fbclient/TCP)
/// usando as credenciais configuradas em [AppConfig].
class FirebirdService {
  static const _networkTimeout = Duration(seconds: 10);

  FbDb? _db;

  Future<void> connect(AppConfig config) async {
    await disconnect();
    try {
      _db = await FbDb.attach(
        host: config.host,
        port: config.port,
        database: config.connectionDatabase,
        user: config.user,
        password: config.password,
      ).timeout(_networkTimeout);
    } catch (e) {
      _db = null;
      throw FirebirdException('Não foi possível conectar ao banco em '
          '${config.host}:${config.port} → ${config.dbPath}\n$e');
    }
  }

  bool get isConnected => _db != null;

  Future<void> disconnect() async {
    try {
      await _db?.detach().timeout(_networkTimeout);
    } catch (_) {
      // ignore
    }
    _db = null;
  }

  FbDb _requireDb() {
    final db = _db;
    if (db == null) {
      throw FirebirdException('Sem conexão com o banco de dados.');
    }
    return db;
  }

  static const _baseColumns = '''
          p.PRD_CODIGO,
          p.PRD_REFERENCIA,
          p.PRD_DESCRICAO,
          p.PRD_PRECO_VENDA,
          p.PRD_UN_VENDA,
          p.PRD_IMAGEM,
          p.PRD_DT_INI_PROM,
          p.PRD_DT_FIM_PROM,
          CASE
            WHEN p.PRD_DT_INI_PROM <= CURRENT_DATE AND p.PRD_DT_FIM_PROM >= CURRENT_DATE
            THEN p.PRD_VALOR_PROM
            ELSE NULL
          END AS PRD_VALOR_PROM_ATIVO
  ''';

  /// Busca produtos por descrição (parcial), código de barras, código do
  /// produto ou referência. Usado pela busca textual manual.
  Future<List<ProductPrice>> search(String term) async {
    final db = _requireDb();
    final trimmed = term.trim();
    if (trimmed.isEmpty) return [];

    final isNumeric = RegExp(r'^\d+$').hasMatch(trimmed);

    final rows = await db.selectAll(
      sql: '''
        SELECT FIRST 50 $_baseColumns
        FROM TB_PRODUTO p
        WHERE p.PRD_STATUS <> 'I'
          AND (
            UPPER(p.PRD_DESCRICAO) CONTAINING UPPER(?)
            OR UPPER(p.PRD_REFERENCIA) CONTAINING UPPER(?)
            OR p.PRD_CODIGO = ?
            OR EXISTS (
              SELECT 1 FROM TB_PROD_CODIGO_BARRAS b
              WHERE CAST(b.PRDC_PRODUTO AS VARCHAR(20)) = p.PRD_CODIGO
                AND b.PRDC_COD_BARRAS = ?
            )
          )
        ORDER BY p.PRD_DESCRICAO
      ''',
      parameters: [trimmed, trimmed, isNumeric ? trimmed : ' ', trimmed],
    ).timeout(_networkTimeout);

    final results = <ProductPrice>[];
    for (final row in rows) {
      results.add(await _buildProductPrice(row));
    }
    return results;
  }

  /// Busca um único produto por código de barras, código do produto ou
  /// referência (correspondência exata). Usado no fluxo de leitura do totem.
  Future<ProductPrice?> lookupByCode(String code) async {
    final db = _requireDb();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;

    final row = await db.selectOne(
      sql: '''
        SELECT FIRST 1 $_baseColumns
        FROM TB_PRODUTO p
        WHERE p.PRD_STATUS <> 'I'
          AND (
            p.PRD_CODIGO = ?
            OR UPPER(p.PRD_REFERENCIA) = UPPER(?)
            OR EXISTS (
              SELECT 1 FROM TB_PROD_CODIGO_BARRAS b
              WHERE CAST(b.PRDC_PRODUTO AS VARCHAR(20)) = p.PRD_CODIGO
                AND b.PRDC_COD_BARRAS = ?
            )
          )
      ''',
      parameters: [trimmed, trimmed, trimmed],
    ).timeout(_networkTimeout);
    if (row == null) return null;
    return _buildProductPrice(row);
  }

  Future<ProductPrice> _buildProductPrice(Map<String, dynamic> row) async {
    final codigo = (_toStringOrNull(row['PRD_CODIGO']) ?? '').trim();
    final precoVenda = _toDouble(row['PRD_PRECO_VENDA']);

    final promoInicio = _toDateOrNull(row['PRD_DT_INI_PROM']);
    final promoFim = _toDateOrNull(row['PRD_DT_FIM_PROM']);
    // Já vem calculado pelo servidor (NULL se hoje está fora do período de
    // PRD_DT_INI_PROM..PRD_DT_FIM_PROM), evitando depender do relógio do celular.
    final promoValor = _toDoubleOrNull(row['PRD_VALOR_PROM_ATIVO']);
    final promoAtiva = (promoValor ?? 0) > 0;

    // Cada bloco de promoção é opcional e não deve derrubar a exibição do
    // preço base do produto caso venha algum dado inesperado (ex.: quando o
    // produto acabou de ganhar sua primeira faixa de quantidade).
    _EncarteInfo? encarte;
    try {
      encarte = await _fetchEncarteAtivo(codigo, precoVenda);
    } catch (_) {
      encarte = null;
    }

    // Regra de prioridade: quando existe promoção por data (TB_PRODUTO) ou
    // de encarte ativa, ela é a promoção principal do produto e a promoção
    // por quantidade (TB_PRODUTO_PROMOCAO) é ignorada.
    List<QuantityTier> faixas = const [];
    if (!promoAtiva && encarte == null) {
      try {
        faixas = await _fetchFaixasQuantidade(codigo);
      } catch (_) {
        faixas = const [];
      }
    }

    String? codigoBarras;
    try {
      codigoBarras = await _fetchCodigoBarras(codigo);
    } catch (_) {
      codigoBarras = null;
    }

    return ProductPrice(
      codigo: codigo,
      referencia: _toStringOrNull(row['PRD_REFERENCIA']),
      descricao: (_toStringOrNull(row['PRD_DESCRICAO']) ?? '').trim(),
      precoVenda: precoVenda,
      unidade: (_toStringOrNull(row['PRD_UN_VENDA']) ?? 'UN').trim(),
      imagem: _toBytes(row['PRD_IMAGEM']),
      codigoBarras: codigoBarras,
      precoPorKg: precoVenda,
      precoPromoData: promoAtiva ? promoValor : null,
      promoDataInicio: promoInicio,
      promoDataFim: promoFim,
      encarteTitulo: encarte?.titulo,
      precoEncarte: encarte?.preco,
      encarteInicio: encarte?.inicio,
      encarteFim: encarte?.fim,
      faixasQuantidade: faixas,
    );
  }

  Future<_EncarteInfo?> _fetchEncarteAtivo(String codigoProduto, double precoVenda) async {
    final db = _requireDb();
    final row = await db.selectOne(
      sql: '''
        SELECT FIRST 1
          pr.PRO_ID,
          pr.PRO_TITULO,
          pr.PRO_DT_INICIO,
          pr.PRO_DT_FIM,
          pce.PRCE_TIPO_VALOR,
          pce.PRCE_VALOR
        FROM TB_PROMOCAO_ENCARTE pce
        JOIN TB_PROMOCAO pr ON pr.PRO_ID = pce.PRCE_PROMOCAO
        WHERE CAST(pce.PRCE_PRODUTO AS VARCHAR(20)) = ?
          AND pr.PRO_DT_INICIO <= CURRENT_DATE
          AND pr.PRO_DT_FIM >= CURRENT_DATE
        ORDER BY pr.PRO_DT_INICIO DESC
      ''',
      parameters: [codigoProduto],
    ).timeout(_networkTimeout);
    if (row == null) return null;

    final tipoValor = _toStringOrNull(row['PRCE_TIPO_VALOR'])?.trim().toUpperCase();
    final valor = _toDoubleOrNull(row['PRCE_VALOR']) ?? 0;
    if (valor <= 0) return null;

    // 'P' = percentual de desconto sobre o preço de venda, outros = valor fixo do produto
    final precoFinal = tipoValor == 'P' ? precoVenda * (1 - valor / 100) : valor;

    return _EncarteInfo(
      promocaoId: _toInt(row['PRO_ID']),
      titulo: (_toStringOrNull(row['PRO_TITULO']) ?? '').trim(),
      inicio: _toDateOrNull(row['PRO_DT_INICIO']),
      fim: _toDateOrNull(row['PRO_DT_FIM']),
      preco: precoFinal,
    );
  }

  /// Faixas de preço por quantidade (TB_PRODUTO_PROMOCAO). Só é consultada
  /// quando o produto não tem promoção por data nem de encarte ativa —
  /// essas duas têm prioridade e substituem a promoção por quantidade.
  Future<List<QuantityTier>> _fetchFaixasQuantidade(String codigoProduto) async {
    final db = _requireDb();
    final tiers = <QuantityTier>[];

    final rows = await db.selectAll(
      sql: '''
        SELECT PRDM_QTDE_INI, PRDM_QTDE_FIM, PRDM_VALOR_PROM, PRDM_TIPO_VALOR
        FROM TB_PRODUTO_PROMOCAO
        WHERE CAST(PRDM_PRODUTO AS VARCHAR(20)) = ?
        ORDER BY PRDM_QTDE_INI
      ''',
      parameters: [codigoProduto],
    ).timeout(_networkTimeout);
    for (final r in rows) {
      tiers.add(QuantityTier(
        qtdeIni: _toDouble(r['PRDM_QTDE_INI']),
        qtdeFim: _toDoubleOrNull(r['PRDM_QTDE_FIM']),
        valor: _toDouble(r['PRDM_VALOR_PROM']),
        isPercentual: _toStringOrNull(r['PRDM_TIPO_VALOR'])?.trim().toUpperCase() == 'P',
      ));
    }

    return tiers;
  }

  /// Busca o código de barras principal (o primeiro cadastrado) de um
  /// produto, usado na etiqueta de gôndola. Ausência de código de barras não
  /// deve impedir a impressão da etiqueta.
  Future<String?> _fetchCodigoBarras(String codigoProduto) async {
    final db = _requireDb();
    final row = await db.selectOne(
      sql: '''
        SELECT FIRST 1 b.PRDC_COD_BARRAS
        FROM TB_PROD_CODIGO_BARRAS b
        WHERE CAST(b.PRDC_PRODUTO AS VARCHAR(20)) = ?
        ORDER BY b.PRDC_COD_BARRAS
      ''',
      parameters: [codigoProduto],
    ).timeout(_networkTimeout);
    if (row == null) return null;
    return _toStringOrNull(row['PRDC_COD_BARRAS'])?.trim();
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  String? _toStringOrNull(dynamic v) {
    if (v == null) return null;
    return v.toString();
  }

  DateTime? _toDateOrNull(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Uint8List? _toBytes(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List) return v;
    if (v is ByteBuffer) return v.asUint8List();
    return null;
  }
}

class _EncarteInfo {
  final int promocaoId;
  final String titulo;
  final DateTime? inicio;
  final DateTime? fim;
  final double? preco;

  _EncarteInfo({
    required this.promocaoId,
    required this.titulo,
    required this.inicio,
    required this.fim,
    required this.preco,
  });
}
