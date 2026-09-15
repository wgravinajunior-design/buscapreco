import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Guarda os banners da tela de espera dentro do diretório de documentos do
/// app.
///
/// O `image_picker` devolve caminhos para cópias no diretório de **cache**,
/// que o Android limpa quando precisa de espaço — num totem que fica meses
/// ligado, isso fazia os banners simplesmente sumirem. Copiando para os
/// documentos do app, eles só somem se o usuário remover ou desinstalar.
class BannerStorage {
  static const _pasta = 'banners';

  static Future<Directory> _diretorio() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_pasta');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copia as imagens escolhidas para o armazenamento definitivo e devolve os
  /// novos caminhos. Uma imagem que falhe ao copiar é ignorada em vez de
  /// derrubar a importação inteira.
  static Future<List<String>> importar(Iterable<String> caminhosOrigem) async {
    final dir = await _diretorio();
    final destinos = <String>[];
    for (final origem in caminhosOrigem) {
      try {
        final extensao = _extensao(origem);
        final nome = '${DateTime.now().microsecondsSinceEpoch}$extensao';
        final destino = '${dir.path}${Platform.pathSeparator}$nome';
        await File(origem).copy(destino);
        destinos.add(destino);
      } catch (_) {
        // Imagem inacessível (cache já limpo, permissão negada): pula.
      }
    }
    return destinos;
  }

  /// Apaga os arquivos da pasta de banners que não estão mais na configuração.
  /// Chamado ao salvar, para que remover um banner não deixe lixo acumulando
  /// no aparelho.
  static Future<void> limparOrfaos(List<String> emUso) async {
    try {
      final dir = await _diretorio();
      final mantidos = emUso.toSet();
      await for (final item in dir.list()) {
        if (item is File && !mantidos.contains(item.path)) {
          try {
            await item.delete();
          } catch (_) {
            // Arquivo em uso por outro processo: tenta de novo no próximo save.
          }
        }
      }
    } catch (_) {
      // Limpeza é best-effort; nunca deve impedir o usuário de salvar.
    }
  }

  static String _extensao(String caminho) {
    final ponto = caminho.lastIndexOf('.');
    final barra = caminho.lastIndexOf(Platform.pathSeparator);
    if (ponto <= barra || ponto == -1) return '.img';
    final ext = caminho.substring(ponto);
    // Evita carregar querystring ou nome estranho para dentro do arquivo.
    return ext.length <= 5 ? ext : '.img';
  }
}
