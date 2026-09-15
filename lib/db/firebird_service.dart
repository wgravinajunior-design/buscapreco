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

  /// Busca um único produto por código de barras, código do produto ou
  /// referência (correspondência exata).
  ///
  /// Tudo que a tela do totem precisa vem numa **única** ida ao servidor:
  /// dados do produto, promoção por data, promoção de encarte ativa e código
  /// de barras principal. Antes eram quatro consultas em sequência por
  /// leitura, o que deixava o totem visivelmente lento em rede de loja.
  Future<ProductPrice?> lookupByCode(String code) async {
    final db = _requireDb();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;

    final row = await db.selectOne(
      sql: '''
        SELECT FIRST 1
          p.PRD_CODIGO,
          p.PRD_REFERENCIA,
          p.PRD_DESCRICAO,
          p.PRD_PRECO_VENDA,
          p.PRD_UN_VENDA,
          p.PRD_IMAGEM,
          CASE
            WHEN p.PRD_DT_INI_PROM <= CURRENT_DATE AND p.PRD_DT_FIM_PROM >= CURRENT_DATE
            THEN p.PRD_VALOR_PROM
            ELSE NULL
          END AS PRD_VALOR_PROM_ATIVO,
          pr.PRO_TITULO,
          pce.PRCE_TIPO_VALOR,
          pce.PRCE_VALOR,
          (SELECT FIRST 1 b2.PRDC_COD_BARRAS
             FROM TB_PROD_CODIGO_BARRAS b2
            WHERE CAST(b2.PRDC_PRODUTO AS VARCHAR(20)) = p.PRD_CODIGO
            ORDER BY b2.PRDC_COD_BARRAS) AS COD_BARRAS
        FROM TB_PRODUTO p
        LEFT JOIN TB_PROMOCAO_ENCARTE pce
               ON CAST(pce.PRCE_PRODUTO AS VARCHAR(20)) = p.PRD_CODIGO
        LEFT JOIN TB_PROMOCAO pr
               ON pr.PRO_ID = pce.PRCE_PROMOCAO
              AND pr.PRO_DT_INICIO <= CURRENT_DATE
              AND pr.PRO_DT_FIM >= CURRENT_DATE
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
        ORDER BY pr.PRO_DT_INICIO DESC NULLS LAST
      ''',
      parameters: [trimmed, trimmed, trimmed],
    ).timeout(_networkTimeout);
    if (row == null) return null;
    return _buildProductPrice(row);
  }

  Future<ProductPrice> _buildProductPrice(Map<String, dynamic> row) async {
    final codigo = (_toStringOrNull(row['PRD_CODIGO']) ?? '').trim();
    final precoVenda = _toDouble(row['PRD_PRECO_VENDA']);

    // Já vem calculado pelo servidor (NULL se hoje está fora do período de
    // PRD_DT_INI_PROM..PRD_DT_FIM_PROM), evitando depender do relógio do celular.
    final promoValor = _toDoubleOrNull(row['PRD_VALOR_PROM_ATIVO']);
    final promoAtiva = (promoValor ?? 0) > 0;

    final precoEncarte = _precoEncarte(row, precoVenda);

    // Regra de prioridade: quando existe promoção por data (TB_PRODUTO) ou
    // de encarte ativa, ela é a promoção principal do produto e a promoção
    // por quantidade (TB_PRODUTO_PROMOCAO) é ignorada.
    List<QuantityTier> faixas = const [];
    if (!promoAtiva && precoEncarte == null) {
      try {
        faixas = await _fetchFaixasQuantidade(codigo);
      } catch (_) {
        // Faixa de quantidade é informação extra; um erro aqui não pode
        // impedir a exibição do preço do produto.
        faixas = const [];
      }
    }

    return ProductPrice(
      codigo: codigo,
      referencia: _toStringOrNull(row['PRD_REFERENCIA']),
      descricao: (_toStringOrNull(row['PRD_DESCRICAO']) ?? '').trim(),
      precoVenda: precoVenda,
      unidade: (_toStringOrNull(row['PRD_UN_VENDA']) ?? 'UN').trim(),
      imagem: _toBytes(row['PRD_IMAGEM']),
      codigoBarras: _toStringOrNull(row['COD_BARRAS'])?.trim(),
      precoPromoData: promoAtiva ? promoValor : null,
      encarteTitulo: precoEncarte == null ? null : _toStringOrNull(row['PRO_TITULO'])?.trim(),
      precoEncarte: precoEncarte,
      faixasQuantidade: faixas,
    );
  }

  /// Preço final vindo do encarte ativo, ou null quando não há encarte válido.
  /// 'P' em PRCE_TIPO_VALOR significa percentual de desconto sobre o preço de
  /// venda; qualquer outro valor é o preço fixo do produto no encarte.
  double? _precoEncarte(Map<String, dynamic> row, double precoVenda) {
    final valor = _toDoubleOrNull(row['PRCE_VALOR']) ?? 0;
    if (valor <= 0) return null;
    final tipoValor = _toStringOrNull(row['PRCE_TIPO_VALOR'])?.trim().toUpperCase();
    return tipoValor == 'P' ? precoVenda * (1 - valor / 100) : valor;
  }

  /// Faixas de preço por quantidade (TB_PRODUTO_PROMOCAO). Só é consultada
  /// quando o produto não tem promoção por data nem de encarte ativa —
  /// essas duas têm prioridade e substituem a promoção por quantidade.
  Future<List<QuantityTier>> _fetchFaixasQuantidade(String codigoProduto) async {
    final db = _requireDb();
    final rows = await db.selectAll(
      sql: '''
        SELECT PRDM_QTDE_INI, PRDM_QTDE_FIM, PRDM_VALOR_PROM, PRDM_TIPO_VALOR
        FROM TB_PRODUTO_PROMOCAO
        WHERE CAST(PRDM_PRODUTO AS VARCHAR(20)) = ?
        ORDER BY PRDM_QTDE_INI
      ''',
      parameters: [codigoProduto],
    ).timeout(_networkTimeout);

    return [
      for (final r in rows)
        QuantityTier(
          qtdeIni: _toDouble(r['PRDM_QTDE_INI']),
          qtdeFim: _toDoubleOrNull(r['PRDM_QTDE_FIM']),
          valor: _toDouble(r['PRDM_VALOR_PROM']),
          isPercentual: _toStringOrNull(r['PRDM_TIPO_VALOR'])?.trim().toUpperCase() == 'P',
        ),
    ];
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

  String? _toStringOrNull(dynamic v) {
    if (v == null) return null;
    return v.toString();
  }

  Uint8List? _toBytes(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List) return v;
    if (v is ByteBuffer) return v.asUint8List();
    return null;
  }
}
