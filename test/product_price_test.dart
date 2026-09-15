import 'package:buscapreco/models/product_price.dart';
import 'package:flutter_test/flutter_test.dart';

ProductPrice _produto({
  double precoVenda = 10.0,
  double? precoEncarte,
  double? precoPromoData,
}) =>
    ProductPrice(
      codigo: '1',
      referencia: null,
      descricao: 'TESTE',
      precoVenda: precoVenda,
      unidade: 'UN',
      precoEncarte: precoEncarte,
      precoPromoData: precoPromoData,
    );

void main() {
  group('melhorPreco', () {
    test('sem promoção usa o preço de venda', () {
      final p = _produto();
      expect(p.melhorPreco, 10.0);
      expect(p.origemMelhorPreco, PromoSource.none);
    });

    test('encarte mais barato vira o melhor preço', () {
      final p = _produto(precoEncarte: 7.5);
      expect(p.melhorPreco, 7.5);
      expect(p.origemMelhorPreco, PromoSource.encarte);
    });

    test('encarte mais caro que o preço de venda é ignorado', () {
      // Cadastro errado no encarte não pode fazer o totem anunciar um preço
      // ACIMA do preço de prateleira.
      final p = _produto(precoVenda: 10.0, precoEncarte: 12.0);
      expect(p.melhorPreco, 10.0);
      expect(p.origemMelhorPreco, PromoSource.none);
    });

    test('encarte tem prioridade sobre promoção por data', () {
      final p = _produto(precoEncarte: 6.0, precoPromoData: 8.0);
      expect(p.melhorPreco, 6.0);
      expect(p.origemMelhorPreco, PromoSource.encarte);
    });

    test('encarte inválido cai para a promoção por data', () {
      final p = _produto(precoEncarte: 99.0, precoPromoData: 8.0);
      expect(p.melhorPreco, 8.0);
      expect(p.origemMelhorPreco, PromoSource.dataProduto);
    });

    test('percentual de desconto nunca é negativo', () {
      expect(_produto(precoEncarte: 12.0).percentualDesconto, 0);
      expect(_produto(precoEncarte: 5.0).percentualDesconto, 50);
    });
  });
}
