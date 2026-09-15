import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final bytes = File('assets/icon/icon.webp').readAsBytesSync();
  final decoded = img.decodeWebP(bytes);
  if (decoded == null) {
    stderr.writeln('Falha ao decodificar o WebP.');
    exit(1);
  }
  File('assets/icon/icon.png').writeAsBytesSync(img.encodePng(decoded));
  stdout.writeln('OK: ${decoded.width}x${decoded.height}');
}
