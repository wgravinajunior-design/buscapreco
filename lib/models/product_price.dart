import 'dart:typed_data';

enum PromoSource { none, dataProduto, encarte, quantidade }

/// Uma faixa de preço por quantidade (encarte ou geral).
class QuantityTier {
  final double qtdeIni;
  final double? qtdeFim;
  final double valor;
  final bool isPercentual;

  QuantityTier({
    required this.qtdeIni,
    required this.qtdeFim,
    required this.valor,
    required this.isPercentual,
  });

  String get label {
    if (qtdeFim == null || qtdeFim == qtdeIni) {
      return 'A partir de ${qtdeIni.toStringAsFixed(0)} un';
    }
    return '${qtdeIni.toStringAsFixed(0)} a ${qtdeFim!.toStringAsFixed(0)} un';
  }
}

class ProductPrice {
  final String codigo;
  final String? referencia;
  final String descricao;
  final double precoVenda;
  final String unidade;
  final Uint8List? imagem;
  final String? codigoBarras;
  final double? precoPorKg;

  // Promoção por data (na própria TB_PRODUTO)
  final double? precoPromoData;
  final DateTime? promoDataInicio;
  final DateTime? promoDataFim;

  // Promoção de encarte ativa
  final String? encarteTitulo;
  final double? precoEncarte;
  final DateTime? encarteInicio;
  final DateTime? encarteFim;

  // Faixas de quantidade (gerais e/ou do encarte)
  final List<QuantityTier> faixasQuantidade;

  ProductPrice({
    required this.codigo,
    required this.referencia,
    required this.descricao,
    required this.precoVenda,
    required this.unidade,
    this.imagem,
    this.codigoBarras,
    this.precoPorKg,
    this.precoPromoData,
    this.promoDataInicio,
    this.promoDataFim,
    this.encarteTitulo,
    this.precoEncarte,
    this.encarteInicio,
    this.encarteFim,
    this.faixasQuantidade = const [],
  });

  bool get temPromoData => precoPromoData != null && precoPromoData! > 0 && precoPromoData! < precoVenda;
  bool get temEncarte => precoEncarte != null && precoEncarte! > 0 && precoEncarte! < precoVenda;
  bool get temFaixaQuantidade => faixasQuantidade.isNotEmpty;

  /// Melhor preço "de balcão" (sem depender de quantidade): encarte tem
  /// prioridade sobre promoção por data, que tem prioridade sobre o preço normal.
  double get melhorPreco {
    if (temEncarte) return precoEncarte!;
    if (temPromoData) return precoPromoData!;
    return precoVenda;
  }

  PromoSource get origemMelhorPreco {
    if (temEncarte) return PromoSource.encarte;
    if (temPromoData) return PromoSource.dataProduto;
    return PromoSource.none;
  }

  double get percentualDesconto {
    if (melhorPreco >= precoVenda || precoVenda == 0) return 0;
    return (1 - (melhorPreco / precoVenda)) * 100;
  }

  /// Produto fictício usado só para pré-visualizar o layout da etiqueta de
  /// gôndola no editor, sem depender de uma leitura real no totem. Já vem
  /// com uma promoção "ativa" para o editor poder mostrar como ficam os
  /// blocos de promoção (preço original, desconto, selo de oferta).
  factory ProductPrice.amostra() => ProductPrice(
        codigo: '12414',
        referencia: null,
        descricao: 'CHOCOLATE BISCUIT LINDT LINDOR MILK 100G',
        precoVenda: 39.90,
        unidade: 'UN',
        codigoBarras: '7610400014649',
        precoPorKg: 399.00,
        precoPromoData: 29.90,
        promoDataInicio: DateTime.now().subtract(const Duration(days: 1)),
        promoDataFim: DateTime.now().add(const Duration(days: 7)),
      );
}
