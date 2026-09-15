import 'package:buscapreco/models/gondola_field.dart';
import 'package:buscapreco/models/product_price.dart';
import 'package:buscapreco/services/gondola_label_service.dart';
import 'package:flutter_test/flutter_test.dart';

ProductPrice _produto({double precoVenda = 39.90, double? precoPromoData}) => ProductPrice(
      codigo: '12414',
      referencia: null,
      descricao: 'Chocolate Lindt 100g',
      precoVenda: precoVenda,
      unidade: 'UN',
      codigoBarras: '7610400014649',
      precoPromoData: precoPromoData,
    );

GondolaFieldConfig _campo(GondolaFieldType tipo, {bool mesmaLinha = false}) =>
    GondolaFieldConfig(tipo: tipo, mesmaLinha: mesmaLinha);

void main() {
  group('textoDoCampo', () {
    test('blocos de promoção somem quando não há desconto', () {
      final p = _produto();
      for (final tipo in GondolaFieldType.values.where((t) => t.somentePromocao)) {
        expect(GondolaLabelService.textoDoCampo(_campo(tipo), p), isNull,
            reason: '${tipo.name} não deveria aparecer sem promoção');
      }
    });

    test('blocos de promoção aparecem com desconto ativo', () {
      final p = _produto(precoPromoData: 29.90);
      expect(GondolaLabelService.textoDoCampo(_campo(GondolaFieldType.percentualDesconto), p), '-25%');
      expect(GondolaLabelService.textoDoCampo(_campo(GondolaFieldType.tituloPromocao), p), 'PROMOÇÃO');
      expect(GondolaLabelService.textoDoCampo(_campo(GondolaFieldType.precoOriginal), p), contains('39,90'));
    });

    test('preço por unidade acompanha o preço promocional', () {
      // Antes este bloco imprimia sempre o preço cheio, contradizendo o preço
      // grande da etiqueta durante uma promoção.
      final texto = GondolaLabelService.textoDoCampo(
        _campo(GondolaFieldType.precoPorUnidade),
        _produto(precoPromoData: 29.90),
      );
      expect(texto, contains('/UN'));
      expect(texto, contains('29,90'));
    });

    test('código de barras é tratado à parte, não como texto', () {
      expect(GondolaLabelService.textoDoCampo(_campo(GondolaFieldType.codigoBarras), _produto()), isNull);
      expect(GondolaLabelService.temConteudo(_campo(GondolaFieldType.codigoBarras), _produto()), isTrue);
    });
  });

  group('agrupar', () {
    test('bloco marcado como "mesma linha" entra no grupo anterior', () {
      final grupos = GondolaLabelService.agrupar([
        _campo(GondolaFieldType.codigoInterno),
        _campo(GondolaFieldType.data, mesmaLinha: true),
      ]);
      expect(grupos, hasLength(1));
      expect(grupos.first, hasLength(2));
    });

    test('no máximo dois blocos por linha', () {
      final grupos = GondolaLabelService.agrupar([
        _campo(GondolaFieldType.codigoInterno),
        _campo(GondolaFieldType.data, mesmaLinha: true),
        _campo(GondolaFieldType.precoPorUnidade, mesmaLinha: true),
      ]);
      expect(grupos.map((g) => g.length), [2, 1]);
    });

    test('código de barras nunca divide linha', () {
      final grupos = GondolaLabelService.agrupar([
        _campo(GondolaFieldType.descricao),
        _campo(GondolaFieldType.codigoBarras, mesmaLinha: true),
        _campo(GondolaFieldType.preco, mesmaLinha: true),
      ]);
      expect(grupos.map((g) => g.length), [1, 1, 1]);
    });
  });

  group('serialização do layout', () {
    test('ida e volta preserva a configuração', () {
      final original = GondolaFieldConfig.padrao();
      original.first
        ..alinhamento = GondolaFieldAlign.direita
        ..tamanho = GondolaFieldSize.gigante
        ..destaque = false;

      final volta = GondolaFieldConfig.desserializar(GondolaFieldConfig.serializar(original));

      expect(volta.map((f) => f.tipo), original.map((f) => f.tipo));
      expect(volta.first.alinhamento, GondolaFieldAlign.direita);
      expect(volta.first.tamanho, GondolaFieldSize.gigante);
      expect(volta.first.destaque, isFalse);
    });

    test('texto corrompido cai no layout padrão em vez de quebrar', () {
      final volta = GondolaFieldConfig.desserializar('lixo:que:nao:existe');
      expect(volta.map((f) => f.tipo), GondolaFieldConfig.padrao().map((f) => f.tipo));
    });

    test('config antiga sem um campo novo ganha o campo desabilitado', () {
      // Simula preferências salvas por uma versão anterior do app.
      final antiga = 'descricao:1:centro:1:normal:0|preco:1:centro:1:grande:0';
      final volta = GondolaFieldConfig.desserializar(antiga);
      expect(volta.map((f) => f.tipo).toSet(), GondolaFieldType.values.toSet());
      expect(volta.firstWhere((f) => f.tipo == GondolaFieldType.data).visivel, isFalse);
    });
  });
}
