import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Monta o código lido por um leitor de código de barras físico, que se
/// comporta como um teclado: digita o código caractere a caractere e termina
/// com Enter (alguns modelos usam Tab).
///
/// Existe como classe separada — em vez de um `TextField` invisível — por um
/// motivo concreto: um campo de texto de linha única chama
/// `focusNode.unfocus()` logo depois do `onSubmitted`
/// (`EditableText._finalizeEditing`). Como o leitor digita cerca de um
/// caractere por milissegundo, os primeiros caracteres da leitura seguinte
/// caíam no vazio enquanto o foco não voltava. O código chegava truncado e
/// então ou não encontrava nada ("produto não encontrado" ao ler o segundo
/// produto), ou casava por acaso com o código interno de outro produto e o
/// totem mostrava o preço errado.
class BarcodeKeyboard {
  /// Tempo máximo entre duas teclas da MESMA leitura. Um leitor envia o código
  /// inteiro em poucos milissegundos; uma pausa maior significa que a leitura
  /// anterior foi abandonada no meio, e o que sobrou não pode ser emendado no
  /// começo da próxima.
  static const intervaloPadraoEntreTeclas = Duration(milliseconds: 500);

  /// Limite de tamanho para o buffer nunca crescer sem controle caso alguém
  /// segure uma tecla ou conecte um teclado de verdade ao totem.
  static const tamanhoMaximoPadrao = 64;

  BarcodeKeyboard({
    required this.aoLerCodigo,
    this.intervaloEntreTeclas = intervaloPadraoEntreTeclas,
    this.tamanhoMaximo = tamanhoMaximoPadrao,
  });

  final void Function(String codigo) aoLerCodigo;
  final Duration intervaloEntreTeclas;
  final int tamanhoMaximo;

  final StringBuffer _digitado = StringBuffer();
  Timer? _timeout;

  /// Só para testes e diagnóstico: o que já foi acumulado da leitura em curso.
  String get parcial => _digitado.toString();

  KeyEventResult aoReceberTecla(KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final tecla = evento.logicalKey;
    if (tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.numpadEnter ||
        tecla == LogicalKeyboardKey.tab) {
      _timeout?.cancel();
      final codigo = _digitado.toString().trim();
      _digitado.clear();
      if (codigo.isNotEmpty) aoLerCodigo(codigo);
      return KeyEventResult.handled;
    }

    final caractere = evento.character;
    // Teclas de controle (Shift, setas, F1...) vêm sem caractere ou com um
    // caractere de controle, e não fazem parte do código.
    if (caractere == null || caractere.isEmpty || caractere.codeUnitAt(0) < 0x20) {
      return KeyEventResult.ignored;
    }

    if (_digitado.length < tamanhoMaximo) {
      _digitado.write(caractere);
    }
    _timeout?.cancel();
    _timeout = Timer(intervaloEntreTeclas, _digitado.clear);
    return KeyEventResult.handled;
  }

  void dispose() {
    _timeout?.cancel();
    _timeout = null;
  }
}
