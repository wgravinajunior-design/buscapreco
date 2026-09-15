import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tela de espera do totem: rotaciona banners promocionais em tela cheia
/// com a faixa "PASSE O PRODUTO" fixa na base, como em totens de autoatendimento.
class IdleCarousel extends StatefulWidget {
  final List<String> imagePaths;
  final int secondsPerImage;
  final Color corPrincipal;

  const IdleCarousel({
    super.key,
    required this.imagePaths,
    required this.secondsPerImage,
    required this.corPrincipal,
  });

  @override
  State<IdleCarousel> createState() => _IdleCarouselState();
}

class _IdleCarouselState extends State<IdleCarousel> {
  final _pageController = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  @override
  void didUpdateWidget(covariant IdleCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compara o conteúdo, não só a quantidade: trocar um banner por outro
    // mantendo o total deixaria o carrossel exibindo a lista antiga.
    if (!listEquals(oldWidget.imagePaths, widget.imagePaths)) {
      _index = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _scheduleNext();
    } else if (oldWidget.secondsPerImage != widget.secondsPerImage) {
      _scheduleNext();
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.imagePaths.length <= 1) return;
    // Duration.zero em Timer.periodic dispara a cada frame e trava o totem;
    // o mínimo de 1s protege contra configuração inválida ou legada.
    final segundos = widget.secondsPerImage < 1 ? 1 : widget.secondsPerImage;
    _timer = Timer.periodic(Duration(seconds: segundos), (_) {
      if (!mounted) return;
      _index = (_index + 1) % widget.imagePaths.length;
      _pageController.animateToPage(
        _index,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.imagePaths.isEmpty
              ? _buildPlaceholder()
              : PageView.builder(
                  controller: _pageController,
                  itemCount: widget.imagePaths.length,
                  itemBuilder: (context, i) => Image.file(
                    File(widget.imagePaths[i]),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    // Banner escolhido da galeria costuma ser uma foto de
                    // vários megapixels. Sem limitar a decodificação, cada
                    // imagem ocupa dezenas de MB na memória — num tablet
                    // barato ligado o dia inteiro isso acaba em OOM.
                    cacheWidth: (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    errorBuilder: (_, _, _) => _buildPlaceholder(),
                  ),
                ),
        ),
        _buildScanBar(),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [widget.corPrincipal, Color.lerp(widget.corPrincipal, Colors.white, 0.25)!],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront, size: 96, color: Colors.white70),
            SizedBox(height: 16),
            Text(
              'Busca Preço',
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanBar() {
    return Container(
      width: double.infinity,
      color: widget.corPrincipal,
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: const Center(
        child: Text(
          'PASSE O PRODUTO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
