import 'package:flutter/material.dart';

/// Paleta de cores predefinida para o cliente personalizar as cores do
/// sistema (faixa de preço, destaque de promoção, etc.) sem precisar digitar
/// códigos hexadecimais.
const List<int> kColorPalette = [
  0xFF13315C, // azul marinho (padrão do sistema)
  0xFF1565C0, // azul
  0xFF00838F, // azul petróleo
  0xFF2E7D32, // verde
  0xFF558B2F, // verde oliva
  0xFFE30613, // vermelho (padrão de promoção)
  0xFFC62828, // vermelho escuro
  0xFFD84315, // laranja queimado
  0xFFE65100, // laranja
  0xFFEF6C00, // âmbar
  0xFF6A1B9A, // roxo
  0xFF4527A0, // índigo
  0xFF283593, // azul índigo escuro
  0xFF37474F, // grafite
  0xFF1C1C1E, // preto suave
  0xFF880E4F, // vinho
];

class ColorPalettePicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const ColorPalettePicker({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kColorPalette.map((value) {
        final isSelected = value == selected;
        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onChanged(value),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Color(value),
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.black : Colors.black12,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]
                  : null,
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
        );
      }).toList(),
    );
  }
}
