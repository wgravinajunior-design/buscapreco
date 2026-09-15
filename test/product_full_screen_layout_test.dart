import 'package:buscapreco/models/product_price.dart';
import 'package:buscapreco/widgets/product_full_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProductPrice _produtoComTudo() => ProductPrice(
      codigo: '12414',
      referencia: null,
      descricao: 'CHOCOLATE BISCUIT LINDT LINDOR MILK AO LEITE CAIXA 100G',
      precoVenda: 39.90,
      unidade: 'UN',
      codigoBarras: '7610400014649',
      precoPromoData: 29.90,
      faixasQuantidade: [
        QuantityTier(qtdeIni: 3, qtdeFim: 5, valor: 27.90, isPercentual: false),
        QuantityTier(qtdeIni: 6, qtdeFim: null, valor: 10, isPercentual: true),
      ],
    );

Future<void> _montar(WidgetTester tester, Size tamanho) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProductFullScreen(
          product: _produtoComTudo(),
          corPrincipal: const Color(0xFF13315C),
          corPromo: const Color(0xFFE30613),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('cabe em tablet retrato', (tester) async {
    await _montar(tester, const Size(800, 1280));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabe em celular retrato estreito', (tester) async {
    await _montar(tester, const Size(360, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cabe em paisagem (orientação habilitada no main.dart)', (tester) async {
    await _montar(tester, const Size(640, 360));
    expect(tester.takeException(), isNull);
  });
}

// Nota: a fonte usada pelo flutter_test é mais larga que a Roboto do
// dispositivo (cada glifo ocupa um quadrado do tamanho da fonte), então estes
// testes são um cenário de estresse — se passam aqui, passam no aparelho.
