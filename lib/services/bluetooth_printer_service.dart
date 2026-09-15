import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterException implements Exception {
  final String message;
  BluetoothPrinterException(this.message);
  @override
  String toString() => message;
}

/// Acesso à mini impressora térmica de etiquetas via Bluetooth clássico
/// (perfil SPP/RFCOMM). A impressora precisa ser pareada uma vez nas
/// configurações de Bluetooth do Android antes de aparecer na lista.
class BluetoothPrinterService {
  /// O app só conversa com impressoras **já pareadas** pelo Android — nunca
  /// faz varredura. Por isso BLUETOOTH_CONNECT basta: pedir BLUETOOTH_SCAN ou
  /// localização só geraria prompts a mais sem necessidade (e localização é
  /// uma permissão sensível que o usuário costuma negar).
  /// Em Android anterior ao 12 o permission_handler já responde "concedida"
  /// sozinho, porque lá a permissão é concedida na instalação.
  static Future<bool> ensurePermissions() async {
    final status = await Permission.bluetoothConnect.request();
    return status.isGranted;
  }

  static Future<List<BluetoothDevice>> listarPareados() async {
    if (!await ensurePermissions()) {
      throw BluetoothPrinterException(
        'Permissão de Bluetooth negada. Autorize o acesso ao Bluetooth nas '
        'configurações do Android para escolher a impressora.',
      );
    }
    try {
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      throw BluetoothPrinterException('Não foi possível listar os dispositivos Bluetooth pareados: $e');
    }
  }

  /// Abre uma conexão nova, envia os bytes e fecha. As mini impressoras
  /// térmicas costumam encerrar a sessão entre impressões, então não vale a
  /// pena manter a conexão aberta entre uma etiqueta e outra.
  static Future<void> enviar(String address, Uint8List bytes) async {
    if (!await ensurePermissions()) {
      throw BluetoothPrinterException(
        'Permissão de Bluetooth negada. Autorize o acesso ao Bluetooth nas '
        'configurações do Android para imprimir a etiqueta.',
      );
    }
    BluetoothConnection? connection;
    try {
      connection = await BluetoothConnection.toAddress(address);
      connection.output.add(bytes);
      await connection.output.allSent;
    } catch (e) {
      throw BluetoothPrinterException(
        'Não foi possível enviar a etiqueta para a impressora Bluetooth. '
        'Verifique se ela está ligada, pareada e ao alcance.\n$e',
      );
    } finally {
      try {
        await connection?.finish();
      } catch (_) {
        // ignore
      }
    }
  }
}
