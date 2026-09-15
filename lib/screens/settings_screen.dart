import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../models/gondola_field.dart';
import '../services/banner_storage.dart';
import '../services/bluetooth_printer_service.dart';
import '../widgets/color_palette_picker.dart';
import 'gondola_label_editor_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppConfig config;
  const SettingsScreen({super.key, required this.config});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _dbPath;
  late final TextEditingController _user;
  late final TextEditingController _password;
  late final TextEditingController _bannerSeconds;
  late List<String> _banners;
  late int _primaryColor;
  late int _promoColor;
  late bool _gondolaEnabled;
  late final TextEditingController _gondolaWidth;
  late final TextEditingController _gondolaHeight;
  late List<GondolaFieldConfig> _gondolaFields;
  String? _gondolaPrinterAddress;
  String? _gondolaPrinterName;
  bool _buscandoImpressoras = false;
  late String _gondolaProtocol;
  late bool _gondolaAutoPrint;
  late final TextEditingController _gondolaPrinterWidthDots;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.config.host);
    _port = TextEditingController(text: widget.config.port.toString());
    _dbPath = TextEditingController(text: widget.config.dbPath);
    _user = TextEditingController(text: widget.config.user);
    _password = TextEditingController(text: widget.config.password);
    _bannerSeconds = TextEditingController(text: widget.config.bannerSeconds.toString());
    _banners = List.of(widget.config.bannerImagePaths);
    _primaryColor = widget.config.primaryColorValue;
    _promoColor = widget.config.promoColorValue;
    _gondolaEnabled = widget.config.gondolaLabelEnabled;
    _gondolaWidth = TextEditingController(text: widget.config.gondolaWidthMm.toStringAsFixed(0));
    _gondolaHeight = TextEditingController(text: widget.config.gondolaHeightMm.toStringAsFixed(0));
    _gondolaFields = GondolaFieldConfig.copiarLista(widget.config.gondolaFields);
    _gondolaPrinterAddress = widget.config.gondolaPrinterAddress;
    _gondolaPrinterName = widget.config.gondolaPrinterName;
    _gondolaProtocol = widget.config.gondolaProtocol;
    _gondolaAutoPrint = widget.config.gondolaAutoPrint;
    _gondolaPrinterWidthDots = TextEditingController(text: widget.config.gondolaPrinterWidthDots.toString());
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _dbPath.dispose();
    _user.dispose();
    _password.dispose();
    _bannerSeconds.dispose();
    _gondolaWidth.dispose();
    _gondolaHeight.dispose();
    _gondolaPrinterWidthDots.dispose();
    super.dispose();
  }

  Future<void> _editarLayoutEtiqueta() async {
    final resultado = await Navigator.of(context).push<List<GondolaFieldConfig>>(
      MaterialPageRoute(builder: (_) => GondolaLabelEditorScreen(campos: _gondolaFields)),
    );
    if (resultado != null) {
      setState(() => _gondolaFields = resultado);
    }
  }

  Future<void> _escolherImpressoraBluetooth() async {
    setState(() => _buscandoImpressoras = true);
    List<BluetoothDevice> dispositivos = [];
    String? erro;
    try {
      dispositivos = await BluetoothPrinterService.listarPareados();
    } catch (e) {
      erro = e.toString();
    } finally {
      if (mounted) setState(() => _buscandoImpressoras = false);
    }
    if (!mounted) return;

    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }

    final escolhido = await showDialog<BluetoothDevice?>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Impressora Bluetooth pareada'),
        children: [
          if (dispositivos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Nenhum dispositivo pareado encontrado. Pareie a impressora nas '
                'configurações de Bluetooth do Android e tente novamente.',
              ),
            ),
          ...dispositivos.map(
            (d) => SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(d),
              child: Text(d.name ?? d.address),
            ),
          ),
        ],
      ),
    );
    if (escolhido != null) {
      setState(() {
        _gondolaPrinterAddress = escolhido.address;
        _gondolaPrinterName = escolhido.name ?? escolhido.address;
      });
    }
  }

  void _removerImpressoraBluetooth() {
    setState(() {
      _gondolaPrinterAddress = null;
      _gondolaPrinterName = null;
    });
  }

  Future<void> _addBanners() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;
    // Copia para o armazenamento definitivo do app: o caminho devolvido pelo
    // image_picker aponta para o cache, que o Android apaga sozinho.
    final salvos = await BannerStorage.importar(picked.map((x) => x.path));
    if (!mounted) return;
    if (salvos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar as imagens escolhidas.')),
      );
      return;
    }
    setState(() => _banners.addAll(salvos));
  }

  void _removeBanner(int index) {
    setState(() => _banners.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    widget.config
      ..host = _host.text.trim()
      ..port = int.parse(_port.text.trim())
      ..dbPath = _dbPath.text.trim()
      ..user = _user.text.trim()
      ..password = _password.text
      ..bannerImagePaths = _banners
      ..bannerSeconds = int.tryParse(_bannerSeconds.text.trim()) ?? 6
      ..primaryColorValue = _primaryColor
      ..promoColorValue = _promoColor
      ..gondolaLabelEnabled = _gondolaEnabled
      ..gondolaWidthMm = double.tryParse(_gondolaWidth.text.trim()) ?? widget.config.gondolaWidthMm
      ..gondolaHeightMm = double.tryParse(_gondolaHeight.text.trim()) ?? widget.config.gondolaHeightMm
      ..gondolaFields = _gondolaFields
      ..gondolaPrinterAddress = _gondolaPrinterAddress
      ..gondolaPrinterName = _gondolaPrinterName
      ..gondolaProtocol = _gondolaProtocol
      ..gondolaAutoPrint = _gondolaAutoPrint
      ..gondolaPrinterWidthDots = int.tryParse(_gondolaPrinterWidthDots.text.trim()) ??
          widget.config.gondolaPrinterWidthDots;
    await widget.config.save();
    // Só agora — depois de confirmado o save — apaga do disco os banners que
    // o usuário removeu, para não acumular imagens órfãs no aparelho.
    await BannerStorage.limparOrfaos(_banners);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuração')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Dados do servidor Firebird 5 (conexão direta via rede)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'IP / Host do servidor',
                hintText: 'ex: 192.168.0.10',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o IP do servidor' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porta',
                hintText: '3050',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Porta inválida';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dbPath,
              decoration: const InputDecoration(
                labelText: 'Caminho da base (.FDB) no servidor',
                hintText: r'D:\OneDrive\DADOS\DUSUCO\DADOS.FDB',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o caminho da base' : null,
            ),
            const SizedBox(height: 20),
            const Text(
              'Credenciais',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Usuário',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o usuário' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Informe a senha' : null,
            ),
            const SizedBox(height: 24),
            const Text(
              'Banners da tela de espera ("Passe o produto")',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Escolha imagens (ex: "Quinta da Carne", "Terça das Frutas") para exibir em '
              'rotação enquanto nenhum produto está sendo lido.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bannerSeconds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Segundos por banner',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              // Sem validação, um 0 aqui viraria Timer.periodic(Duration.zero)
              // no carrossel — trocando de banner a cada frame e travando o totem.
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n < 1) return 'Informe ao menos 1 segundo';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ..._banners.asMap().entries.map((e) => _BannerThumb(
                      path: e.value,
                      onRemove: () => _removeBanner(e.key),
                    )),
                InkWell(
                  onTap: _addBanners,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_photo_alternate_outlined, size: 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Paleta de cores do sistema',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Personalize as cores da tela de preço de acordo com a identidade visual da sua loja.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Text('Cor principal (faixa de preço)', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ColorPalettePicker(
              selected: _primaryColor,
              onChanged: (v) => setState(() => _primaryColor = v),
            ),
            const SizedBox(height: 18),
            Text('Cor de destaque de promoção', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ColorPalettePicker(
              selected: _promoColor,
              onChanged: (v) => setState(() => _promoColor = v),
            ),
            const SizedBox(height: 24),
            const Text(
              'Impressão de etiqueta de gôndola',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Ao ativar, um botão de impressão aparece na tela do totem quando um '
              'produto é lido, gerando a etiqueta no modelo padrão de gôndola '
              '(descrição, código de barras, código interno e preço).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Habilitar impressão de etiqueta'),
              value: _gondolaEnabled,
              onChanged: (v) => setState(() => _gondolaEnabled = v),
            ),
            if (_gondolaEnabled) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _gondolaWidth,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Largura (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Largura inválida';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _gondolaHeight,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Altura (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) return 'Altura inválida';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('Layout da etiqueta'),
                subtitle: const Text(
                  'Escolha quais blocos aparecem, em que ordem, alinhamento, tamanho e '
                  'agrupamento — inclusive os campos de promoção.',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _editarLayoutEtiqueta,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _gondolaPrinterAddress != null ? Icons.print : Icons.print_disabled,
                  color: _gondolaPrinterAddress != null ? Colors.green : Colors.grey,
                ),
                title: Text(_gondolaPrinterName ?? 'Nenhuma impressora Bluetooth selecionada'),
                subtitle: Text(
                  _gondolaPrinterAddress != null
                      ? 'A etiqueta é enviada direto para essa impressora, sem diálogo.'
                      : 'Sem impressora, será usado o diálogo de impressão do sistema.',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: _buscandoImpressoras
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _buscandoImpressoras ? null : _escolherImpressoraBluetooth,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: Text(_gondolaPrinterAddress == null ? 'Selecionar impressora' : 'Trocar impressora'),
                  ),
                  if (_gondolaPrinterAddress != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _removerImpressoraBluetooth,
                      child: const Text('Remover'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Text('Protocolo da impressora', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(
                'ESC/POS (a maioria das mini impressoras Bluetooth vendidas como '
                '"impressora de etiqueta") imprime com comandos nativos de texto e '
                'código de barras, sem depender de imagem — mais confiável em '
                'impressoras genéricas. Use TSPL só para impressoras de etiqueta de '
                'verdade, com sensor de gap (ex.: Zjiang, Xprinter, Gainscha).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: AppConfig.protocoloEscPos, label: Text('ESC/POS (mais comum)')),
                  ButtonSegment(value: AppConfig.protocoloTspl, label: Text('TSPL')),
                ],
                selected: {_gondolaProtocol},
                onSelectionChanged: (v) => setState(() => _gondolaProtocol = v.first),
              ),
              const SizedBox(height: 12),
              Text('Largura de impressão da impressora', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Text(
                'Precisa bater com a bobina/etiqueta física da impressora, senão a '
                'imagem sai cortada ou embaralhada. Valores comuns: 384 pontos '
                '(bobina de 58mm) ou 576 pontos (bobina de 80mm) — confira no manual '
                'da impressora se tiver dúvida.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _gondolaPrinterWidthDots,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Largura (pontos)',
                  hintText: '384',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                // Valor zerado/negativo quebraria o cálculo de DPI e a largura
                // do bitmap enviado para a impressora.
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 8) return 'Largura inválida (ex.: 384 ou 576)';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Imprimir automaticamente ao ler o produto'),
                subtitle: const Text(
                  'Assim que o código de barras é lido, a etiqueta já é enviada para a '
                  'impressora, sem precisar tocar no botão de impressão.',
                  style: TextStyle(fontSize: 12),
                ),
                value: _gondolaAutoPrint,
                onChanged: (v) => setState(() => _gondolaAutoPrint = v),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerThumb extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  const _BannerThumb({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 90,
              height: 90,
              color: Colors.grey.shade300,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            icon: const Icon(Icons.cancel, color: Colors.redAccent),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
