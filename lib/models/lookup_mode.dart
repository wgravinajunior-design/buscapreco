/// Por qual campo o totem procura o produto lido.
///
/// O mesmo texto lido pode existir em mais de um lugar do cadastro — o código
/// de barras de um produto pode ser o código interno ou a referência de outro.
/// Procurar nos três campos ao mesmo tempo fazia o totem exibir, de vez em
/// quando, um produto que não corresponde ao que foi passado no leitor.
/// Deixar o lojista escolher o campo elimina a ambiguidade.
enum LookupMode {
  codigoBarras,
  codigo,
  referencia;

  static const padrao = LookupMode.codigoBarras;

  /// Converte o valor salvo nas preferências, caindo no padrão se o texto for
  /// desconhecido (configuração de uma versão anterior ou corrompida).
  static LookupMode porNome(String? nome) {
    if (nome == null) return padrao;
    for (final modo in LookupMode.values) {
      if (modo.name == nome) return modo;
    }
    return padrao;
  }
}

extension LookupModeLabel on LookupMode {
  String get rotulo => switch (this) {
    LookupMode.codigoBarras => 'Código de barras',
    LookupMode.codigo => 'Código',
    LookupMode.referencia => 'Referência',
  };

  String get descricao => switch (this) {
    LookupMode.codigoBarras =>
      'Procura o texto lido entre os códigos de barras cadastrados do produto '
          '(TB_PROD_CODIGO_BARRAS). É o normal para um totem de loja.',
    LookupMode.codigo =>
      'Procura pelo código interno do produto (PRD_CODIGO). Use quando as '
          'etiquetas da loja trazem o código do cadastro, não o código de barras.',
    LookupMode.referencia =>
      'Procura pela referência do produto (PRD_REFERENCIA). Use quando a loja '
          'identifica a mercadoria pela referência do fornecedor.',
  };
}
