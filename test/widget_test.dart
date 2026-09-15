import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buscapreco/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const BuscaPrecoApp());
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
