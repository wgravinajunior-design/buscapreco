import 'dart:typed_data';
import 'package:fbdb/fbdb.dart';
import '../config/app_config.dart';
import '../models/lookup_mode.dart';
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

  /// Busca os produtos correspondentes ao [code] pelo campo indicado em [modo]:
  /// código de barras (consultando TB_PROD_CODIGO_BARRAS e TB_PRODUTO_UNIDADE),
  /// código interno ou referência.
  ///
  /// Retorna a lista de produtos encontrados. Se houver mais de um produto
  /// associado ao mesmo código lido, a tela poderá exibir a seleção.
  Future<List<ProductPrice>> lookupProducts(String code, {required LookupMode modo}) async {
    final db = _requireDb();
    final trimmed = code.trim();
    if (trimmed.isEmpty) return const [];

    final codigos = <String>{trimmed};
    if (modo == LookupMode.codigoBarras) {
      // Remove todos os zeros à esquerda (ex: '007898652371929' -> '7898652371929')
      final semZeros = trimmed.replaceFirst(RegExp(r'^0+'), '');
      if (semZeros.isNotEmpty && semZeros != trimmed) {
        codigos.add(semZeros);
      }
      // Se tiver 13 dígitos numéricos, adiciona com 0 à esquerda (GTIN-14 no banco)
      if (trimmed.length == 13 && RegExp(r'^\d+$').hasMatch(trimmed)) {
        codigos.add('0$trimmed');
      }
      // Código de 14 dígitos iniciando com 0 (GTIN-14 enviando 0 à esquerda para EAN-13)
      if (trimmed.length == 14 && trimmed.startsWith('0')) {
        codigos.add(trimmed.substring(1));
      }
      // Código de 12 dígitos (UPC-A) que no banco pode estar como EAN-13 com 0
      if (trimmed.length == 12 && RegExp(r'^\d+$').hasMatch(trimmed)) {
        codigos.add('0$trimmed');
      }
      // Etiqueta de balança (13 dígitos iniciado com '2', padrão brasileiro de açougue/padaria)
      // Padrão: 2 [CCCCC] [VVVVVV] [D] -> extrai o código interno do produto
      if (trimmed.length == 13 && trimmed.startsWith('2') && RegExp(r'^\d+$').hasMatch(trimmed)) {
        final cod5 = trimmed.substring(1, 6);
        final cod5Num = int.tryParse(cod5);
        if (cod5Num != null && cod5Num > 0) {
          codigos.add(cod5Num.toString());
          codigos.add(cod5);
        }
        final cod4 = trimmed.substring(1, 5);
        final cod4Num = int.tryParse(cod4);
        if (cod4Num != null && cod4Num > 0) {
          codigos.add(cod4Num.toString());
        }
        final cod6 = trimmed.substring(1, 7);
        final cod6Num = int.tryParse(cod6);
        if (cod6Num != null && cod6Num > 0) {
          codigos.add(cod6Num.toString());
        }
      }
    }

    final listaCodigos = codigos.toList();
    final placeholders = List.filled(listaCodigos.length, '?').join(', ');

    // Subquery deduplicada de encarte: garante que se o produto estiver em mais de um
    // encarte vigente ao mesmo tempo, selecione apenas o mais recente, sem duplicar o produto.
    const subqueryEncarte = '''
      LEFT JOIN (
        SELECT
          pce.PRCE_PRODUTO,
          pce.PRCE_TIPO_VALOR,
          pce.PRCE_VALOR,
          pr.PRO_TITULO,
          pr.PRO_DT_INICIO
        FROM TB_PROMOCAO_ENCARTE pce
        JOIN TB_PROMOCAO pr ON pr.PRO_ID = pce.PRCE_PROMOCAO
        WHERE pr.PRO_DT_INICIO <= CURRENT_DATE
          AND pr.PRO_DT_FIM >= CURRENT_DATE
          AND pce.PRCE_ID = (
            SELECT FIRST 1 pce2.PRCE_ID
            FROM TB_PROMOCAO_ENCARTE pce2
            JOIN TB_PROMOCAO pr2 ON pr2.PRO_ID = pce2.PRCE_PROMOCAO
            WHERE pce2.PRCE_PRODUTO = pce.PRCE_PRODUTO
              AND pr2.PRO_DT_INICIO <= CURRENT_DATE
              AND pr2.PRO_DT_FIM >= CURRENT_DATE
            ORDER BY pr2.PRO_DT_INICIO DESC, pce2.PRCE_ID DESC
          )
      ) enc ON enc.PRCE_PRODUTO = p.PRD_ID
    ''';

    final (sql, params) = switch (modo) {
      LookupMode.codigoBarras => (
        '''
        SELECT
          p.PRD_ID,
          p.PRD_CODIGO,
          p.PRD_REFERENCIA,
          p.PRD_DESCRICAO,
          COALESCE(NULLIF(origem.PRECO_VENDA, 0), p.PRD_PRECO_VENDA) AS PRD_PRECO_VENDA,
          COALESCE(NULLIF(TRIM(origem.UNIDADE), ''), p.PRD_UN_VENDA, 'UN') AS PRD_UN_VENDA,
          p.PRD_IMAGEM,
          CASE
            WHEN p.PRD_DT_INI_PROM <= CURRENT_DATE AND p.PRD_DT_FIM_PROM >= CURRENT_DATE
            THEN p.PRD_VALOR_PROM
            ELSE NULL
          END AS PRD_VALOR_PROM_ATIVO,
          enc.PRO_TITULO,
          enc.PRCE_TIPO_VALOR,
          enc.PRCE_VALOR,
          origem.COD_BARRAS
        FROM (
          -- Origem 1: Tabela de códigos de barras adicionais e principais
          SELECT
            b.PRDC_PRODUTO AS PROD_ID,
            b.PRDC_COD_BARRAS AS COD_BARRAS,
            NULL AS UNIDADE,
            CAST(NULL AS NUMERIC(15, 6)) AS PRECO_VENDA
          FROM TB_PROD_CODIGO_BARRAS b
          WHERE TRIM(b.PRDC_COD_BARRAS) IN ($placeholders)

          UNION

          -- Origem 2: Tabela de unidades alternativas do produto (ex: caixas, fardos)
          SELECT
            u.PRDU_PRODUTO AS PROD_ID,
            u.PRDU_COD_BARRAS AS COD_BARRAS,
            u.PRDU_UNIDADE AS UNIDADE,
            u.PRDU_PRECO_VENDA AS PRECO_VENDA
          FROM TB_PRODUTO_UNIDADE u
          WHERE TRIM(u.PRDU_COD_BARRAS) IN ($placeholders)

          UNION

          -- Origem 3: Produtos cujo código de barras foi cadastrado diretamente em PRD_CODIGO
          SELECT
            p0.PRD_ID AS PROD_ID,
            p0.PRD_CODIGO AS COD_BARRAS,
            p0.PRD_UN_VENDA AS UNIDADE,
            p0.PRD_PRECO_VENDA AS PRECO_VENDA
          FROM TB_PRODUTO p0
          WHERE TRIM(p0.PRD_CODIGO) IN ($placeholders)
        ) origem
        JOIN TB_PRODUTO p ON p.PRD_ID = origem.PROD_ID
        $subqueryEncarte
        WHERE (p.PRD_STATUS IS NULL OR p.PRD_STATUS <> 'I')
        ORDER BY enc.PRO_DT_INICIO DESC NULLS LAST, p.PRD_DESCRICAO, p.PRD_ID
        ''',
        [...listaCodigos, ...listaCodigos, ...listaCodigos],
      ),
      LookupMode.codigo => (
        '''
        SELECT
          p.PRD_ID,
          p.PRD_CODIGO,
          p.PRD_REFERENCIA,
          p.PRD_DESCRICAO,
          p.PRD_PRECO_VENDA,
          COALESCE(p.PRD_UN_VENDA, 'UN') AS PRD_UN_VENDA,
          p.PRD_IMAGEM,
          CASE
            WHEN p.PRD_DT_INI_PROM <= CURRENT_DATE AND p.PRD_DT_FIM_PROM >= CURRENT_DATE
            THEN p.PRD_VALOR_PROM
            ELSE NULL
          END AS PRD_VALOR_PROM_ATIVO,
          enc.PRO_TITULO,
          enc.PRCE_TIPO_VALOR,
          enc.PRCE_VALOR,
          COALESCE(
            (SELECT FIRST 1 b2.PRDC_COD_BARRAS
               FROM TB_PROD_CODIGO_BARRAS b2
              WHERE b2.PRDC_PRODUTO = p.PRD_ID
                AND b2.PRDC_COD_BARRAS IS NOT NULL
              ORDER BY b2.PRDC_COD_BARRAS),
            (SELECT FIRST 1 u2.PRDU_COD_BARRAS
               FROM TB_PRODUTO_UNIDADE u2
              WHERE u2.PRDU_PRODUTO = p.PRD_ID
                AND u2.PRDU_COD_BARRAS IS NOT NULL
              ORDER BY u2.PRDU_COD_BARRAS)
          ) AS COD_BARRAS
        FROM TB_PRODUTO p
        $subqueryEncarte
        WHERE (p.PRD_STATUS IS NULL OR p.PRD_STATUS <> 'I')
          AND (TRIM(p.PRD_CODIGO) = ? OR CAST(p.PRD_ID AS VARCHAR(20)) = ?)
        ORDER BY enc.PRO_DT_INICIO DESC NULLS LAST, p.PRD_DESCRICAO, p.PRD_ID
        ''',
        [trimmed, trimmed],
      ),
      LookupMode.referencia => (
        '''
        SELECT
          p.PRD_ID,
          p.PRD_CODIGO,
          p.PRD_REFERENCIA,
          p.PRD_DESCRICAO,
          p.PRD_PRECO_VENDA,
          COALESCE(p.PRD_UN_VENDA, 'UN') AS PRD_UN_VENDA,
          p.PRD_IMAGEM,
          CASE
            WHEN p.PRD_DT_INI_PROM <= CURRENT_DATE AND p.PRD_DT_FIM_PROM >= CURRENT_DATE
            THEN p.PRD_VALOR_PROM
            ELSE NULL
          END AS PRD_VALOR_PROM_ATIVO,
          enc.PRO_TITULO,
          enc.PRCE_TIPO_VALOR,
          enc.PRCE_VALOR,
          COALESCE(
            (SELECT FIRST 1 b2.PRDC_COD_BARRAS
               FROM TB_PROD_CODIGO_BARRAS b2
              WHERE b2.PRDC_PRODUTO = p.PRD_ID
                AND b2.PRDC_COD_BARRAS IS NOT NULL
              ORDER BY b2.PRDC_COD_BARRAS),
            (SELECT FIRST 1 u2.PRDU_COD_BARRAS
               FROM TB_PRODUTO_UNIDADE u2
              WHERE u2.PRDU_PRODUTO = p.PRD_ID
                AND u2.PRDU_COD_BARRAS IS NOT NULL
              ORDER BY u2.PRDU_COD_BARRAS)
          ) AS COD_BARRAS
        FROM TB_PRODUTO p
        $subqueryEncarte
        WHERE (p.PRD_STATUS IS NULL OR p.PRD_STATUS <> 'I')
          AND (UPPER(TRIM(p.PRD_REFERENCIA)) = UPPER(?)
               OR p.PRD_ID IN (SELECT u2.PRDU_PRODUTO FROM TB_PRODUTO_UNIDADE u2 WHERE UPPER(TRIM(u2.PRDU_REFERENCIA)) = UPPER(?)))
        ORDER BY enc.PRO_DT_INICIO DESC NULLS LAST, p.PRD_DESCRICAO, p.PRD_ID
        ''',
        [trimmed, trimmed],
      ),
    };

    final rows = await db.selectAll(
      sql: sql,
      parameters: params,
    ).timeout(_networkTimeout);

    if (rows.isEmpty) return const [];

    final produtos = <ProductPrice>[];
    final vistos = <String>{};

    for (final row in rows) {
      final p = await _buildProductPrice(row);
      // Garante que o mesmo produto na mesma unidade e preço não se repita
      final chave = '${p.id ?? p.codigo}_${p.unidade}_${p.precoVenda}';
      if (vistos.add(chave)) {
        produtos.add(p);
      }
    }

    return produtos;
  }

  /// Busca um único produto pelo campo indicado em [modo] (compatibilidade).
  Future<ProductPrice?> lookupByCode(String code, {required LookupMode modo}) async {
    final list = await lookupProducts(code, modo: modo);
    return list.isEmpty ? null : list.first;
  }

  Future<ProductPrice> _buildProductPrice(Map<String, dynamic> row) async {
    final id = _toIntOrNull(row['PRD_ID']);
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
    if (!promoAtiva && precoEncarte == null && id != null) {
      try {
        faixas = await _fetchFaixasQuantidade(id);
      } catch (_) {
        // Faixa de quantidade é informação extra; um erro aqui não pode
        // impedir a exibição do preço do produto.
        faixas = const [];
      }
    }

    return ProductPrice(
      id: id,
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

  /// Faixas de preço por quantidade (TB_PRODUTO_PROMOCAO). Vinculadas
  /// ao PRD_ID (PRDM_PRODUTO) do produto.
  Future<List<QuantityTier>> _fetchFaixasQuantidade(int idProduto) async {
    final db = _requireDb();
    final rows = await db.selectAll(
      sql: '''
        SELECT PRDM_QTDE_INI, PRDM_QTDE_FIM, PRDM_VALOR_PROM, PRDM_TIPO_VALOR
        FROM TB_PRODUTO_PROMOCAO
        WHERE PRDM_PRODUTO = ?
        ORDER BY PRDM_QTDE_INI
      ''',
      parameters: [idProduto],
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

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
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
