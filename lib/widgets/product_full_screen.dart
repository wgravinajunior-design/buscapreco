import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_price.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Exibição em tela cheia do produto lido, no estilo de totens de
/// autoatendimento: foto no topo e faixa de preço grande na base. Quando há
/// promoção, o preço vem em destaque (maior e na cor de promoção), como numa
/// etiqueta de oferta de loja. As cores vêm da configuração para o cliente
/// poder personalizar de acordo com a identidade visual da loja.
class ProductFullScreen extends StatelessWidget {
  final ProductPrice product;
  final Color corPrincipal;
  final Color corPromo;

  const ProductFullScreen({
    super.key,
    required this.product,
    required this.corPrincipal,
    required this.corPromo,
  });

  @override
  Widget build(BuildContext context) {
    final origem = product.origemMelhorPreco;
    final temDesconto = product.melhorPreco < product.precoVenda;

    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: product.imagem != null
                  ? Image.memory(product.imagem!, fit: BoxFit.contain)
                  : Icon(Icons.inventory_2_outlined, size: 160, color: Colors.grey.shade300),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          color: corPrincipal,
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (temDesconto)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: corPromo,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      origem == PromoSource.encarte
                          ? 'OFERTA DE ENCARTE · -${product.percentualDesconto.toStringAsFixed(0)}%'
                          : 'PROMOÇÃO · -${product.percentualDesconto.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              Text(
                product.descricao,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cód. ${product.codigo}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (temDesconto)
                Text(
                  _moeda.format(product.precoVenda),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 24,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              _PriceTag(
                value: product.melhorPreco,
                unidade: product.unidade,
                destaque: temDesconto,
                corPromo: corPromo,
              ),
              if (product.temFaixaQuantidade) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 6,
                  children: product.faixasQuantidade
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${t.label}: ${t.isPercentual ? '-${t.valor.toStringAsFixed(0)}%' : _moeda.format(t.valor)}',
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Preço grande no estilo de etiqueta: reais em destaque e centavos menores
/// sobrescritos, igual às etiquetas de promoção de loja física.
class _PriceTag extends StatelessWidget {
  final double value;
  final String unidade;
  final bool destaque;
  final Color corPromo;

  const _PriceTag({
    required this.value,
    required this.unidade,
    required this.destaque,
    required this.corPromo,
  });

  @override
  Widget build(BuildContext context) {
    // Arredonda para centavos ANTES de separar reais/centavos: sem isso um
    // valor como 9.999 vira "R$ 9,99" em vez de "R$ 10,00".
    final centavosTotais = (value * 100).round();
    final reais = centavosTotais ~/ 100;
    final centavos = centavosTotais % 100;
    final cor = destaque ? corPromo : Colors.white;

    final conteudo = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'R\$',
            style: TextStyle(color: cor, fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          '$reais',
          style: TextStyle(
            color: cor,
            fontSize: destaque ? 92 : 64,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            ',${centavos.toString().padLeft(2, '0')}',
            style: TextStyle(color: cor, fontSize: 34, fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, left: 8),
          child: Text(
            unidade,
            style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );

    if (!destaque) return conteudo;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: conteudo,
    );
  }
}
