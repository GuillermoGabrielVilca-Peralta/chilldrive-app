import 'package:flutter_test/flutter_test.dart';
import 'package:chilldrive_app/utils/validaciones.dart';

void main() {
  group('esCorreoValido', () {
    test('correo bien formado → true', () {
      expect(esCorreoValido('ana@correo.com'), isTrue);
      expect(esCorreoValido('a.b-c@sub.dominio.pe'), isTrue);
    });

    test('recorta espacios alrededor', () {
      expect(esCorreoValido('  ana@correo.com  '), isTrue);
    });

    test('sin @ → false', () {
      expect(esCorreoValido('anacorreo.com'), isFalse);
    });

    test('sin dominio o sin TLD → false', () {
      expect(esCorreoValido('ana@'), isFalse);
      expect(esCorreoValido('ana@correo'), isFalse);
    });

    test('vacío o con espacios internos → false', () {
      expect(esCorreoValido(''), isFalse);
      expect(esCorreoValido('ana @correo.com'), isFalse);
      expect(esCorreoValido('ana@corr eo.com'), isFalse);
    });
  });
}
