import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gondola_field.dart';

/// Configuração de conexão com o Firebird, do totem e das cores do sistema,
/// persistida localmente.
class AppConfig {
  static const _kHost = 'fb_host';
  static const _kPort = 'fb_port';
  static const _kDbPath = 'fb_dbpath';
  static const _kUser = 'fb_user';
  static const _kPassword = 'fb_password';
  static const _kBanners = 'kiosk_banners';
  static const _kBannerSeconds = 'kiosk_banner_seconds';
  static const _kPrimaryColor = 'ui_primary_color';
  static const _kPromoColor = 'ui_promo_color';
  static const _kGondolaEnabled = 'gondola_enabled';
  static const _kGondolaWidthMm = 'gondola_width_mm';
  static const _kGondolaHeightMm = 'gondola_height_mm';
  static const _kGondolaFields = 'gondola_fields';
  static const _kGondolaPrinterAddress = 'gondola_printer_address';
  static const _kGondolaPrinterName = 'gondola_printer_name';
  static const _kGondolaProtocol = 'gondola_protocol';
  static const _kGondolaAutoPrint = 'gondola_auto_print';
  static const _kGondolaPrinterWidthDots = 'gondola_printer_width_dots';

  static const int defaultPrimaryColor = 0xFF13315C; // azul padrão
  static const int defaultPromoColor = 0xFFE30613; // vermelho padrão
  static const double defaultGondolaWidthMm = 90;
  static const double defaultGondolaHeightMm = 40;

  /// Protocolo da mini impressora térmica: a grande maioria dos modelos
  /// genéricos vendidos como "impressora de etiqueta" na verdade só entende
  /// comandos ESC/POS (o mesmo de impressora de cupom). TSPL é o protocolo
  /// de impressoras de etiqueta "de verdade" (com sensor de gap).
  static const String protocoloEscPos = 'escpos';
  static const String protocoloTspl = 'tspl';

  /// Largura de impressão física padrão em pontos, usada quando nada foi
  /// configurado: 384 pontos ≈ impressoras de bobina de 58mm (as mais
  /// comuns entre as mini impressoras Bluetooth genéricas).
  static const int defaultGondolaPrinterWidthDots = 384;

  String host;
  int port;
  String dbPath;
  String user;
  String password;
  List<String> bannerImagePaths;
  int bannerSeconds;
  int primaryColorValue;
  int promoColorValue;
  bool gondolaLabelEnabled;
  double gondolaWidthMm;
  double gondolaHeightMm;
  /// Quais blocos aparecem na etiqueta, em que ordem, alinhamento e destaque
  /// — a "disposição" configurável pelo usuário no editor de etiqueta.
  List<GondolaFieldConfig> gondolaFields;
  String? gondolaPrinterAddress;
  String? gondolaPrinterName;
  String gondolaProtocol;
  bool gondolaAutoPrint;
  int gondolaPrinterWidthDots;

  AppConfig({
    required this.host,
    required this.port,
    required this.dbPath,
    required this.user,
    required this.password,
    required this.bannerImagePaths,
    required this.bannerSeconds,
    required this.primaryColorValue,
    required this.promoColorValue,
    required this.gondolaLabelEnabled,
    required this.gondolaWidthMm,
    required this.gondolaHeightMm,
    required this.gondolaFields,
    this.gondolaPrinterAddress,
    this.gondolaPrinterName,
    this.gondolaProtocol = protocoloEscPos,
    this.gondolaAutoPrint = false,
    this.gondolaPrinterWidthDots = defaultGondolaPrinterWidthDots,
  });

  Color get primaryColor => Color(primaryColorValue);
  Color get promoColor => Color(promoColorValue);

  factory AppConfig.defaults() => AppConfig(
        host: '192.168.0.1',
        port: 3060,
        dbPath: r'D:\OneDrive\DADOS\DUSUCO\DADOS.FDB',
        user: 'SYSDBA',
        password: 'masterkey',
        bannerImagePaths: const [],
        bannerSeconds: 6,
        primaryColorValue: defaultPrimaryColor,
        promoColorValue: defaultPromoColor,
        gondolaLabelEnabled: false,
        gondolaWidthMm: defaultGondolaWidthMm,
        gondolaHeightMm: defaultGondolaHeightMm,
        gondolaFields: GondolaFieldConfig.padrao(),
      );

  /// Valor gravado por uma versão anterior do app (ou por um formulário que
  /// ainda não validava) não pode voltar como zero/negativo: isso vira
  /// `Timer.periodic(Duration.zero)` no carrossel, bitmap de largura zero na
  /// impressora e página PDF de dimensão inválida na etiqueta.
  static T _minimo<T extends num>(T? valor, T minimo, T padrao) {
    if (valor == null) return padrao;
    return valor < minimo ? padrao : valor;
  }

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = AppConfig.defaults();
    return AppConfig(
      host: prefs.getString(_kHost) ?? defaults.host,
      port: prefs.getInt(_kPort) ?? defaults.port,
      dbPath: prefs.getString(_kDbPath) ?? defaults.dbPath,
      user: prefs.getString(_kUser) ?? defaults.user,
      password: prefs.getString(_kPassword) ?? defaults.password,
      bannerImagePaths: prefs.getStringList(_kBanners) ?? defaults.bannerImagePaths,
      bannerSeconds: _minimo(prefs.getInt(_kBannerSeconds), 1, defaults.bannerSeconds),
      primaryColorValue: prefs.getInt(_kPrimaryColor) ?? defaults.primaryColorValue,
      promoColorValue: prefs.getInt(_kPromoColor) ?? defaults.promoColorValue,
      gondolaLabelEnabled: prefs.getBool(_kGondolaEnabled) ?? defaults.gondolaLabelEnabled,
      gondolaWidthMm: _minimo(prefs.getDouble(_kGondolaWidthMm), 1.0, defaults.gondolaWidthMm),
      gondolaHeightMm: _minimo(prefs.getDouble(_kGondolaHeightMm), 1.0, defaults.gondolaHeightMm),
      gondolaFields: GondolaFieldConfig.desserializar(prefs.getString(_kGondolaFields)),
      gondolaPrinterAddress: prefs.getString(_kGondolaPrinterAddress),
      gondolaPrinterName: prefs.getString(_kGondolaPrinterName),
      gondolaProtocol: prefs.getString(_kGondolaProtocol) ?? defaults.gondolaProtocol,
      gondolaAutoPrint: prefs.getBool(_kGondolaAutoPrint) ?? defaults.gondolaAutoPrint,
      gondolaPrinterWidthDots: _minimo(
        prefs.getInt(_kGondolaPrinterWidthDots),
        8,
        defaults.gondolaPrinterWidthDots,
      ),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, host);
    await prefs.setInt(_kPort, port);
    await prefs.setString(_kDbPath, dbPath);
    await prefs.setString(_kUser, user);
    await prefs.setString(_kPassword, password);
    await prefs.setStringList(_kBanners, bannerImagePaths);
    await prefs.setInt(_kBannerSeconds, bannerSeconds);
    await prefs.setInt(_kPrimaryColor, primaryColorValue);
    await prefs.setInt(_kPromoColor, promoColorValue);
    await prefs.setBool(_kGondolaEnabled, gondolaLabelEnabled);
    await prefs.setDouble(_kGondolaWidthMm, gondolaWidthMm);
    await prefs.setDouble(_kGondolaHeightMm, gondolaHeightMm);
    await prefs.setString(_kGondolaFields, GondolaFieldConfig.serializar(gondolaFields));
    if (gondolaPrinterAddress != null) {
      await prefs.setString(_kGondolaPrinterAddress, gondolaPrinterAddress!);
    } else {
      await prefs.remove(_kGondolaPrinterAddress);
    }
    if (gondolaPrinterName != null) {
      await prefs.setString(_kGondolaPrinterName, gondolaPrinterName!);
    } else {
      await prefs.remove(_kGondolaPrinterName);
    }
    await prefs.setString(_kGondolaProtocol, gondolaProtocol);
    await prefs.setBool(_kGondolaAutoPrint, gondolaAutoPrint);
    await prefs.setInt(_kGondolaPrinterWidthDots, gondolaPrinterWidthDots);
  }

  /// Caminho no formato aceito pelo fbclient para conexão remota via TCP/IP.
  String get connectionDatabase => dbPath;
}
