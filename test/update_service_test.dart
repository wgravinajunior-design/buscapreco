import 'package:buscapreco/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UpdateService.compararVersoes', () {
    test('versao maior detectada', () {
      expect(UpdateService.compararVersoes('1.0.1', '1.0.0'), greaterThan(0));
      expect(UpdateService.compararVersoes('1.1.0', '1.0.9'), greaterThan(0));
      expect(UpdateService.compararVersoes('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compararVersoes('v1.0.2', 'v1.0.1'), greaterThan(0));
      expect(UpdateService.compararVersoes('1.0.10', '1.0.2'), greaterThan(0));
    });

    test('versao igual detectada', () {
      expect(UpdateService.compararVersoes('1.0.0', '1.0.0'), equals(0));
      expect(UpdateService.compararVersoes('v1.0.1', '1.0.1'), equals(0));
      expect(UpdateService.compararVersoes('1.0', '1.0.0'), equals(0));
    });

    test('versao menor detectada', () {
      expect(UpdateService.compararVersoes('1.0.0', '1.0.1'), lessThan(0));
      expect(UpdateService.compararVersoes('1.0.2', '1.0.10'), lessThan(0));
      expect(UpdateService.compararVersoes('v0.9.9', '1.0.0'), lessThan(0));
    });
  });
}
