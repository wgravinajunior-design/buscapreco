import 'package:buscapreco/models/product_price.dart';
import 'package:buscapreco/widgets/multiple_products_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MultipleProductsModal exibe lista de produtos e dispara onSelect ao tocar',
      (WidgetTester tester) async {
    ProductPrice? selecionado;
    bool cancelou = false;

    final produtos = [
      ProductPrice(
        id: 1,
        codigo: '101',
        referencia: 'REF-A',
        descricao: 'FANTA LARANJA 350ML',
        precoVenda: 5.50,
        unidade: 'UN',
        codigoBarras: '7894900050011',
      ),
      ProductPrice(
        id: 2,
        codigo: '102',
        referencia: 'REF-B',
        descricao: 'FANTA UVA 350ML',
        precoVenda: 5.00,
        unidade: 'UN',
        codigoBarras: '7894900050011',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultipleProductsModal(
            products: produtos,
            onSelect: (p) => selecionado = p,
            onCancel: () => cancelou = true,
            corPrincipal: const Color(0xFF13315C),
            corPromo: const Color(0xFFE30613),
          ),
        ),
      ),
    );

    // Verifica se os dois produtos estão visíveis na tela
    expect(find.text('FANTA LARANJA 350ML'), findsOneWidget);
    expect(find.text('FANTA UVA 350ML'), findsOneWidget);
    expect(find.text('Mais de um produto encontrado'), findsOneWidget);

    // Toca no segundo produto
    await tester.tap(find.text('FANTA UVA 350ML'));
    await tester.pump();

    expect(selecionado, isNotNull);
    expect(selecionado!.id, 2);
    expect(selecionado!.descricao, 'FANTA UVA 350ML');

    // Toca em Cancelar
    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(cancelou, isTrue);
  });
}
