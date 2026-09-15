import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buscapreco/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const BuscaPrecoApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('a tela do totem não usa TextField para o leitor', (WidgetTester tester) async {
    await tester.pumpWidget(const BuscaPrecoApp());
    await tester.pump();

    // Um TextField de linha única chama focusNode.unfocus() depois do
    // onSubmitted, e o leitor de código de barras perde os primeiros
    // caracteres da leitura seguinte — era a causa de "produto não encontrado"
    // na segunda leitura e do produto trocado. A leitura tem que chegar por um
    // receptor de teclas puro.
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(EditableText), findsNothing);
  });
}
