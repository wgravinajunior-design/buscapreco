import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../db/firebird_service.dart';
import '../models/product_price.dart';
import '../services/gondola_label_service.dart';
import '../widgets/idle_carousel.dart';
import '../widgets/product_full_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// Tela principal do totem: fica em modo de espera (carrossel de banners)
/// aguardando a leitura de um código de barras (leitor físico atuando como
/// teclado, ou a câmera), e mostra o produto em tela cheia por alguns
/// segundos antes de voltar ao carrossel.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = FirebirdService();
  final _scanFocusNode = FocusNode();
  final _scanController = TextEditingController();

  AppConfig? _config;
  bool _connecting = false;
  String? _connectionError;

  ProductPrice? _product;
  String? _lookupError;
  bool _looking = false;
  Timer? _revertTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _revertTimer?.cancel();
    _scanFocusNode.dispose();
    _scanController.dispose();
    _service.disconnect();
    super.dispose();
  }

  Future<void> _init() async {
    final config = await AppConfig.load();
    if (!mounted) return;
    setState(() => _config = config);
    await _connect();
  }

  Future<void> _connect() async {
    if (_config == null) return;
    if (_connecting) return;
    setState(() {
      _connecting = true;
      _connectionError = null;
    });
    try {
      await _service.connect(_config!);
    } catch (e) {
      if (mounted) setState(() => _connectionError = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _openSettings() async {
    if (_config == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsScreen(config: _config!)),
    );
    if (saved == true) {
      setState(() {});
      await _connect();
    }
    _scanFocusNode.requestFocus();
  }

  Future<void> _printGondolaLabel() async {
    final config = _config;
    final product = _product;
    if (config == null || product == null) return;
    try {
      await GondolaLabelService.imprimir(product, config);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao gerar etiqueta: $e')),
      );
    }
  }

  Future<void> _scanWithCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    _scanFocusNode.requestFocus();
    if (code != null && code.isNotEmpty) {
      await _lookup(code);
    }
  }

  Future<void> _lookup(String code) async {
    // Evita disparar duas consultas simultâneas na mesma conexão (o que
    // corrompe o protocolo do Firebird com "Error writing data to the
    // connection"), caso o leitor de código de barras dispare mais de um
    // evento para a mesma leitura.
    if (_looking) return;
    if (!_service.isConnected) {
      setState(() => _lookupError = 'Sem conexão com o banco de dados. Verifique a configuração.');
      _scheduleRevert(seconds: 4);
      return;
    }
    setState(() {
      _looking = true;
      _lookupError = null;
    });
    try {
      final result = await _service.lookupByCode(code);
      _aplicarResultado(result);
    } catch (e) {
      // A conexão pode ter caído (rede instável, timeout do servidor, etc.).
      // Tenta reconectar uma vez em segundo plano e refazer a leitura antes
      // de desistir, para não depender de fechar e abrir o app.
      try {
        await _connect();
        final result = await _service.lookupByCode(code);
        _aplicarResultado(result);
      } catch (e2) {
        if (!mounted) return;
        setState(() => _lookupError = 'Falha na conexão com o banco. Tentando novamente...\n$e2');
        _scheduleRevert(seconds: 4);
      }
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  void _aplicarResultado(ProductPrice? result) {
    if (!mounted) return;
    setState(() {
      _product = result;
      _lookupError = result == null ? 'Produto não encontrado.' : null;
    });
    _scheduleRevert(seconds: result == null ? 3 : 8);
    final config = _config;
    if (result != null && config != null && config.gondolaLabelEnabled && config.gondolaAutoPrint) {
      _printGondolaLabel();
    }
  }

  void _scheduleRevert({required int seconds}) {
    _revertTimer?.cancel();
    _revertTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      setState(() {
        _product = null;
        _lookupError = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _buildContent(config),
            ),
            // Campo invisível que recebe a leitura de um leitor de código de
            // barras físico (que se comporta como um teclado + Enter).
            Positioned(
              width: 1,
              height: 1,
              left: -100,
              child: Opacity(
                opacity: 0,
                child: TextField(
                  focusNode: _scanFocusNode,
                  controller: _scanController,
                  autofocus: true,
                  keyboardType: TextInputType.none,
                  onSubmitted: (v) {
                    _scanController.clear();
                    if (v.trim().isNotEmpty) _lookup(v.trim());
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  if ((_config?.gondolaLabelEnabled ?? false) && _product != null)
                    IconButton(
                      tooltip: 'Imprimir etiqueta de gôndola',
                      icon: const Icon(Icons.print, color: Colors.white70),
                      onPressed: _printGondolaLabel,
                    ),
                  IconButton(
                    tooltip: 'Ler com a câmera',
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.white70),
                    onPressed: _scanWithCamera,
                  ),
                  IconButton(
                    tooltip: 'Status da conexão / Reconectar',
                    icon: Icon(
                      _service.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: _service.isConnected ? Colors.greenAccent : Colors.redAccent,
                    ),
                    onPressed: _connecting ? null : _connect,
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    icon: const Icon(Icons.settings, color: Colors.white70),
                    onPressed: _openSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppConfig? config) {
    final corPrincipal = Color(config?.primaryColorValue ?? AppConfig.defaultPrimaryColor);
    if (config == null || _connecting) {
      return ColoredBox(
        color: corPrincipal,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_connectionError != null) {
      return ColoredBox(
        color: corPrincipal,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, color: Colors.white70, size: 56),
                const SizedBox(height: 16),
                Text(
                  _connectionError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: _connect, child: const Text('Tentar novamente')),
              ],
            ),
          ),
        ),
      );
    }
    if (_looking) {
      return ColoredBox(
        color: corPrincipal,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_lookupError != null) {
      return ColoredBox(
        color: corPrincipal,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search_off, color: Colors.white70, size: 56),
                const SizedBox(height: 16),
                Text(
                  _lookupError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_product != null) {
      return ProductFullScreen(
        product: _product!,
        corPrincipal: corPrincipal,
        corPromo: config.promoColor,
      );
    }
    return IdleCarousel(
      imagePaths: config.bannerImagePaths,
      secondsPerImage: config.bannerSeconds,
      corPrincipal: corPrincipal,
    );
  }
}
