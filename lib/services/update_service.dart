import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_version.dart';

/// Informações do último release obtido do GitHub.
class ReleaseInfo {
  final bool sucesso;
  final String? erro;
  final String tagName;
  final String versaoRemota;
  final String notas;
  final String? apkUrl;
  final String? apkNome;
  final int apkTamanho;
  final bool temAtualizacao;

  const ReleaseInfo({
    required this.sucesso,
    this.erro,
    this.tagName = '',
    this.versaoRemota = '',
    this.notas = '',
    this.apkUrl,
    this.apkNome,
    this.apkTamanho = 0,
    this.temAtualizacao = false,
  });

  factory ReleaseInfo.erro(String mensagem) {
    return ReleaseInfo(sucesso: false, erro: mensagem);
  }

  factory ReleaseInfo.semAtualizacao({String versao = ''}) {
    return ReleaseInfo(
      sucesso: true,
      versaoRemota: versao,
      temAtualizacao: false,
    );
  }
}

/// Serviço de auto-atualização do totem via GitHub Releases.
class UpdateService {
  static const _channel = MethodChannel('com.dusuco.buscapreco/updater');
  static const _networkTimeout = Duration(seconds: 10);

  /// Compara duas versões em formato semver (ex: "1.0.1" e "1.0.0").
  /// Retorna:
  ///   > 0 se v1 > v2
  ///   = 0 se v1 == v2
  ///   < 0 se v1 < v2
  static int compararVersoes(String v1, String v2) {
    final limpa1 = v1.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final limpa2 = v2.trim().replaceFirst(RegExp(r'^[vV]'), '');

    final partes1 = limpa1.split('.');
    final partes2 = limpa2.split('.');
    final maxLen = partes1.length > partes2.length ? partes1.length : partes2.length;

    for (var i = 0; i < maxLen; i++) {
      final p1 = i < partes1.length ? (int.tryParse(partes1[i]) ?? 0) : 0;
      final p2 = i < partes2.length ? (int.tryParse(partes2[i]) ?? 0) : 0;
      if (p1 != p2) return p1 - p2;
    }
    return 0;
  }

  /// Consulta o GitHub Releases pelo último release publicado.
  static Future<ReleaseInfo> verificarAtualizacao() async {
    final client = HttpClient();
    client.connectionTimeout = _networkTimeout;

    try {
      final url = Uri.parse(
        'https://api.github.com/repos/${AppVersion.githubOwner}/${AppVersion.githubRepo}/releases/latest',
      );

      final request = await client.getUrl(url).timeout(_networkTimeout);
      // GitHub API exige User-Agent em todas as requisições
      request.headers.set('User-Agent', 'BuscaPreco-Totem-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(_networkTimeout);

      if (response.statusCode == 404) {
        // Ainda não há releases publicados no repositório
        return ReleaseInfo.semAtualizacao();
      }

      if (response.statusCode != 200) {
        return ReleaseInfo.erro('Servidor retornou status ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final Map<String, dynamic> json = jsonDecode(body);

      final tagName = (json['tag_name'] as String? ?? '').trim();
      final versaoRemota = tagName.replaceFirst(RegExp(r'^[vV]'), '');
      final notas = (json['body'] as String? ?? '').trim();

      String? apkUrl;
      String? apkNome;
      int apkTamanho = 0;

      final assets = json['assets'] as List<dynamic>? ?? const [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final nome = (asset['name'] as String? ?? '').toLowerCase();
          if (nome.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            apkNome = asset['name'] as String?;
            apkTamanho = (asset['size'] as num? ?? 0).toInt();
            break;
          }
        }
      }

      final temAtualizacao = versaoRemota.isNotEmpty &&
          apkUrl != null &&
          compararVersoes(versaoRemota, AppVersion.version) > 0;

      return ReleaseInfo(
        sucesso: true,
        tagName: tagName,
        versaoRemota: versaoRemota,
        notas: notas,
        apkUrl: apkUrl,
        apkNome: apkNome,
        apkTamanho: apkTamanho,
        temAtualizacao: temAtualizacao,
      );
    } catch (e) {
      return ReleaseInfo.erro('Falha ao verificar atualizações: $e');
    } finally {
      client.close();
    }
  }

  /// Baixa o APK da [url] informada e chama o instalador do Android.
  /// [onProgresso] recebe (bytesBaixados, bytesTotal).
  static Future<void> baixarEInstalarApk(
    String url, {
    void Function(int baixado, int total)? onProgresso,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = _networkTimeout;

    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_networkTimeout);
      request.headers.set('User-Agent', 'BuscaPreco-Totem-App');
      final response = await request.close().timeout(_networkTimeout);

      if (response.statusCode != 200) {
        throw Exception('Download falhou com código HTTP ${response.statusCode}');
      }

      final total = response.contentLength;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/buscapreco-update.apk');

      // Se já existia download antigo, remove para não corromper
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      var baixado = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        baixado += chunk.length;
        if (onProgresso != null) {
          onProgresso(baixado, total);
        }
      }
      await sink.flush();
      await sink.close();

      // Dispara a instalação nativa
      if (Platform.isAndroid) {
        await _channel.invokeMethod('installApk', {'filePath': apkFile.path});
      } else {
        debugPrint('Arquivo APK baixado em: ${apkFile.path}');
      }
    } finally {
      client.close();
    }
  }
}
