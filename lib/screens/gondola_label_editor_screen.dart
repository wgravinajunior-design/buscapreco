import 'package:flutter/material.dart';

import '../models/gondola_field.dart';
import '../models/product_price.dart';
import '../services/gondola_label_service.dart';

/// Editor visual do layout da etiqueta de gôndola. Como a impressão (ESC/POS
/// ou TSPL) é sequencial de cima para baixo, "editar a disposição" aqui
/// significa: quais blocos aparecem, em que ordem, alinhados para qual lado,
/// com que tamanho/destaque, e se dois blocos dividem a mesma linha — é
/// exatamente isso que controla o resultado no papel. O preview reaproveita
/// a mesma lógica de texto/agrupamento do serviço de impressão, então fica
/// fiel ao que sai impresso.
class GondolaLabelEditorScreen extends StatefulWidget {
  final List<GondolaFieldConfig> campos;
  const GondolaLabelEditorScreen({super.key, required this.campos});

  @override
  State<GondolaLabelEditorScreen> createState() => _GondolaLabelEditorScreenState();
}

class _GondolaLabelEditorScreenState extends State<GondolaLabelEditorScreen> {
  late List<GondolaFieldConfig> _campos;
  final _amostra = ProductPrice.amostra();

  @override
  void initState() {
    super.initState();
    _campos = GondolaFieldConfig.copiarLista(widget.campos);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor de etiqueta'),
        actions: [
          IconButton(
            tooltip: 'Salvar',
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(_campos),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.grey.shade200,
            padding: const EdgeInsets.all(20),
            child: Center(child: _Preview(campos: _campos, produto: _amostra)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Arraste pelo ícone à direita para reordenar. Os blocos de promoção só '
              'aparecem na etiqueta quando o produto tem desconto ativo.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: _campos.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = _campos.removeAt(oldIndex);
                  _campos.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) => _CampoTile(
                key: ValueKey(_campos[index].tipo),
                index: index,
                campo: _campos[index],
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoTile extends StatelessWidget {
  final int index;
  final GondolaFieldConfig campo;
  final VoidCallback onChanged;

  const _CampoTile({required super.key, required this.index, required this.campo, required this.onChanged});

  IconData _iconeAlinhamento(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => Icons.format_align_left,
        GondolaFieldAlign.centro => Icons.format_align_center,
        GondolaFieldAlign.direita => Icons.format_align_right,
      };

  @override
  Widget build(BuildContext context) {
    final corAtivo = Theme.of(context).colorScheme.primary;
    final podeCompartilharLinha = campo.tipo.podeCompartilharLinha;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: campo.visivel,
                  onChanged: (v) {
                    campo.visivel = v ?? true;
                    onChanged();
                  },
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        campo.tipo.rotulo,
                        style: TextStyle(
                          fontWeight: campo.visivel ? FontWeight.w600 : FontWeight.normal,
                          color: campo.visivel ? null : Colors.grey,
                        ),
                      ),
                      if (campo.tipo.somentePromocao)
                        Text(
                          'Só aparece com promoção ativa',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Alinhamento: ${campo.alinhamento.rotulo} (toque para trocar)',
                    icon: Icon(_iconeAlinhamento(campo.alinhamento)),
                    onPressed: () {
                      campo.alinhamento =
                          GondolaFieldAlign.values[(campo.alinhamento.index + 1) % GondolaFieldAlign.values.length];
                      onChanged();
                    },
                  ),
                  IconButton(
                    tooltip: campo.destaque ? 'Remover negrito' : 'Negrito',
                    icon: Icon(Icons.format_bold, color: campo.destaque ? corAtivo : Colors.grey),
                    onPressed: () {
                      campo.destaque = !campo.destaque;
                      onChanged();
                    },
                  ),
                  IconButton(
                    tooltip: !podeCompartilharLinha
                        ? 'Código de barras sempre fica na própria linha'
                        : (campo.mesmaLinha
                            ? 'Não juntar com o bloco anterior'
                            : 'Juntar com o bloco anterior na mesma linha'),
                    icon: Icon(
                      Icons.merge_type,
                      color: !podeCompartilharLinha ? Colors.grey.shade300 : (campo.mesmaLinha ? corAtivo : Colors.grey),
                    ),
                    onPressed: !podeCompartilharLinha
                        ? null
                        : () {
                            campo.mesmaLinha = !campo.mesmaLinha;
                            onChanged();
                          },
                  ),
                  const SizedBox(width: 4),
                  ...GondolaFieldSize.values.map((tamanho) => _chipTamanho(context, corAtivo, tamanho)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipTamanho(BuildContext context, Color corAtivo, GondolaFieldSize tamanho) {
    final ativo = campo.tamanho == tamanho;
    final rotuloCurto = switch (tamanho) {
      GondolaFieldSize.normal => 'N',
      GondolaFieldSize.grande => 'G',
      GondolaFieldSize.gigante => 'GG',
    };
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        campo.tamanho = tamanho;
        onChanged();
      },
      child: Tooltip(
        message: 'Tamanho: ${tamanho.rotulo}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: ativo ? corAtivo.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: ativo ? corAtivo : Colors.grey.shade300),
          ),
          child: Text(
            rotuloCurto,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ativo ? corAtivo : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Simula visualmente a bobina de papel térmico, renderizando os blocos
/// visíveis na mesma ordem/alinhamento/tamanho/agrupamento que sairão
/// impressos — reaproveita a mesma lógica de conteúdo e agrupamento do
/// serviço de impressão.
class _Preview extends StatelessWidget {
  final List<GondolaFieldConfig> campos;
  final ProductPrice produto;
  const _Preview({required this.campos, required this.produto});

  TextAlign _textAlign(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => TextAlign.left,
        GondolaFieldAlign.centro => TextAlign.center,
        GondolaFieldAlign.direita => TextAlign.right,
      };

  Alignment _alignment(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => Alignment.centerLeft,
        GondolaFieldAlign.centro => Alignment.center,
        GondolaFieldAlign.direita => Alignment.centerRight,
      };

  CrossAxisAlignment _crossAxis(GondolaFieldAlign a) => switch (a) {
        GondolaFieldAlign.esquerda => CrossAxisAlignment.start,
        GondolaFieldAlign.centro => CrossAxisAlignment.center,
        GondolaFieldAlign.direita => CrossAxisAlignment.end,
      };

  double _tamanhoBase(GondolaFieldType tipo) => switch (tipo) {
        GondolaFieldType.descricao => 13,
        GondolaFieldType.codigoBarras => 11,
        GondolaFieldType.preco => 16,
        GondolaFieldType.codigoInterno => 11,
        GondolaFieldType.data => 11,
        GondolaFieldType.precoPorUnidade => 11,
        GondolaFieldType.precoOriginal => 12,
        GondolaFieldType.percentualDesconto => 13,
        GondolaFieldType.tituloPromocao => 12,
      };

  @override
  Widget build(BuildContext context) {
    final visiveis = campos.where((c) => c.visivel && GondolaLabelService.temConteudo(c, produto)).toList();
    final grupos = GondolaLabelService.agrupar(visiveis);
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: grupos.isEmpty
            ? const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Nenhum bloco visível', style: TextStyle(color: Colors.grey))),
                ),
              ]
            : grupos.map(_linhaDoGrupo).toList(),
      ),
    );
  }

  Widget _linhaDoGrupo(List<GondolaFieldConfig> grupo) {
    if (grupo.length == 1) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: _conteudo(grupo.first));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: grupo.map((c) => Expanded(child: _conteudo(c))).toList(),
      ),
    );
  }

  Widget _conteudo(GondolaFieldConfig campo) {
    if (campo.tipo == GondolaFieldType.codigoBarras) {
      return Column(
        crossAxisAlignment: _crossAxis(campo.alinhamento),
        children: [
          Align(
            alignment: _alignment(campo.alinhamento),
            child: SizedBox(height: 34, width: 150, child: CustomPaint(painter: _BarrasFakePainter())),
          ),
          const SizedBox(height: 2),
          Text(
            produto.codigoBarras!,
            textAlign: _textAlign(campo.alinhamento),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
      );
    }

    final texto = GondolaLabelService.textoDoCampo(campo, produto) ?? '';
    return Text(
      texto,
      textAlign: _textAlign(campo.alinhamento),
      style: TextStyle(
        fontFamily: 'monospace',
        fontWeight: campo.destaque ? FontWeight.bold : FontWeight.normal,
        fontSize: _tamanhoBase(campo.tipo) * campo.tamanho.multiplicador,
        decoration: campo.tipo == GondolaFieldType.precoOriginal ? TextDecoration.lineThrough : null,
      ),
    );
  }
}

/// Barras verticais decorativas só para o preview lembrar um código de
/// barras — a impressão de verdade usa o código de barras nativo da
/// impressora (ESC/POS) ou desenhado no PDF (TSPL/diálogo do sistema).
class _BarrasFakePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final preto = Paint()..color = Colors.black;
    const larguras = [2.0, 1.0, 3.0, 1.0, 2.0, 4.0, 1.0, 2.0, 1.0, 3.0, 2.0, 1.0, 4.0, 1.0, 2.0, 3.0, 1.0, 2.0];
    var x = 0.0;
    var desenha = true;
    for (final largura in larguras) {
      if (x >= size.width) break;
      if (desenha) {
        canvas.drawRect(Rect.fromLTWH(x, 0, largura, size.height), preto);
      }
      x += largura;
      desenha = !desenha;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
