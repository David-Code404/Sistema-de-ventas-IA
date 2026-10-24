import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/widgets/pago_dialog.dart';

void main() {
  group('CI', () {
    test('acepta 5 a 10 digitos y complemento', () {
      for (final v in ['12345', '1234567', '1234567890', '1234567-1A', '1234567-1a']) {
        expect(validarDocumento('CI', v), isNull, reason: v);
      }
    });
    test('rechaza letras, cortos, largos y espacios', () {
      for (final v in ['abcd', '1234', '12345678901', '123 456', '1234567-AA', '-----']) {
        expect(validarDocumento('CI', v), isNotNull, reason: v);
      }
    });
  });

  group('NIT', () {
    test('solo numeros de 7 a 13 digitos', () {
      expect(validarDocumento('NIT', '1020304050'), isNull);
      expect(validarDocumento('NIT', '10203A0'), isNotNull);
      expect(validarDocumento('NIT', '123456'), isNotNull);
    });
  });

  group('EXTRANJERO', () {
    test('acepta DNI y pasaportes', () {
      for (final v in ['45678912', 'AB123456', '12345678-K']) {
        expect(validarDocumento('EXTRANJERO', v), isNull, reason: v);
      }
    });
    test('rechaza sin numeros o muy cortos', () {
      for (final v in ['ABCDEFG', '12345', '----12', 'AB 12345']) {
        expect(validarDocumento('EXTRANJERO', v), isNotNull, reason: v);
      }
    });
  });
}
