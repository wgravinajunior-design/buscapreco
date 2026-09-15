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
  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return statuses[Permission.bluetoothConnect]?.isGranted ?? false;
  }

  static Future<List<BluetoothDevice>> listarPareados() async {
    await ensurePermissions();
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
    await ensurePermissions();
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
