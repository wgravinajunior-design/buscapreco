import 'package:buscapreco/services/barcode_keyboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Teclas com caractere imprimível (dígitos do código).
KeyEvent _digito(String c) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.digit0,
  logicalKey: LogicalKeyboardKey.digit0,
  character: c,
  timeStamp: Duration.zero,
);

KeyEvent _enter() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.enter,
  logicalKey: LogicalKeyboardKey.enter,
  timeStamp: Duration.zero,
);

KeyEvent _tab() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.tab,
  logicalKey: LogicalKeyboardKey.tab,
  timeStamp: Duration.zero,
);

KeyEvent _shift() => const KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.shiftLeft,
  logicalKey: LogicalKeyboardKey.shiftLeft,
  timeStamp: Duration.zero,
);

void _ler(BarcodeKeyboard teclado, String codigo, {bool enter = true}) {
  for (final c in codigo.split('')) {
    teclado.aoReceberTecla(_digito(c));
  }
  if (enter) teclado.aoReceberTecla(_enter());
}

void main() {
  late List<String> lidos;
  late BarcodeKeyboard teclado;

  setUp(() {
    lidos = [];
    teclado = BarcodeKeyboard(aoLerCodigo: lidos.add);
  });

  tearDown(() => teclado.dispose());

  test('monta o código e entrega no Enter', () {
    _ler(teclado, '7891234567890');
    expect(lidos, ['7891234567890']);
  });

  test('a SEGUNDA leitura chega inteira — o bug relatado', () {
    // Com o TextField invisível, o campo perdia o foco depois do onSubmitted
    // e os primeiros caracteres da leitura seguinte se perdiam: a segunda
    // leitura dava "produto não encontrado" ou trazia produto trocado.
    _ler(teclado, '7891234567890');
    _ler(teclado, '7899876543210');
    _ler(teclado, '7891111111111');
    expect(lidos, ['7891234567890', '7899876543210', '7891111111111']);
  });

  test('aceita Tab como terminador (alguns leitores usam)', () {
    _ler(teclado, '12345', enter: false);
    teclado.aoReceberTecla(_tab());
    expect(lidos, ['12345']);
  });

  test('teclas de controle não entram no código', () {
    teclado.aoReceberTecla(_shift());
    _ler(teclado, '123');
    expect(lidos, ['123']);
  });

  test('Enter sozinho não dispara consulta', () {
    teclado.aoReceberTecla(_enter());
    expect(lidos, isEmpty);
  });

  test('ignora KeyUp para não duplicar caracteres', () {
    teclado.aoReceberTecla(_digito('1'));
    teclado.aoReceberTecla(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.digit1,
        logicalKey: LogicalKeyboardKey.digit1,
        timeStamp: Duration.zero,
      ),
    );
    teclado.aoReceberTecla(_enter());
    expect(lidos, ['1']);
  });

  test('limita o tamanho do código', () {
    final teclado = BarcodeKeyboard(aoLerCodigo: lidos.add, tamanhoMaximo: 5);
    addTearDown(teclado.dispose);
    _ler(teclado, '1234567890');
    expect(lidos, ['12345']);
  });

  testWidgets('leitura abandonada no meio não contamina a próxima', (tester) async {
    final teclado = BarcodeKeyboard(
      aoLerCodigo: lidos.add,
      intervaloEntreTeclas: const Duration(milliseconds: 50),
    );
    addTearDown(teclado.dispose);

    // Metade de um código, sem Enter (cliente tirou o produto cedo demais).
    _ler(teclado, '789123', enter: false);
    expect(teclado.parcial, '789123');

    // Passado o intervalo, o buffer é descartado.
    await tester.pump(const Duration(milliseconds: 60));
    expect(teclado.parcial, isEmpty);

    // A leitura seguinte não vem emendada com o resto da anterior.
    _ler(teclado, '5554443332221');
    expect(lidos, ['5554443332221']);
  });
}
