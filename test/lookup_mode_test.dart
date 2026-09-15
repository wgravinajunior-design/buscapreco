import 'package:buscapreco/models/lookup_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o padrão é código de barras', () {
    expect(LookupMode.padrao, LookupMode.codigoBarras);
    expect(LookupMode.porNome(null), LookupMode.codigoBarras);
  });

  test('lê o valor salvo nas preferências', () {
    for (final modo in LookupMode.values) {
      expect(LookupMode.porNome(modo.name), modo);
    }
  });

  test('valor desconhecido volta ao padrão em vez de quebrar', () {
    expect(LookupMode.porNome('qualquer_coisa'), LookupMode.codigoBarras);
    expect(LookupMode.porNome(''), LookupMode.codigoBarras);
  });

  test('todo modo tem rótulo e descrição', () {
    for (final modo in LookupMode.values) {
      expect(modo.rotulo, isNotEmpty);
      expect(modo.descricao, isNotEmpty);
    }
  });
}
