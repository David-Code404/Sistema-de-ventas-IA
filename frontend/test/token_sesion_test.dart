// Prueba del token de sesion: el cliente HTTP lo agrega a cada peticion y, si el
// servidor responde 401, cierra la sesion y manda al login. No necesita servidor.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/models/cliente_http.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/navegacion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Session.cerrar);

  test('sin sesion no se envia Authorization', () async {
    String? cabecera = 'x';
    final cliente = ClienteConToken(MockClient((req) async {
      cabecera = req.headers['Authorization'];
      return http.Response('{}', 200);
    }));
    await cliente.get(Uri.parse('http://api/productos'));
    expect(cabecera, isNull);
  });

  test('con sesion se envia Authorization: Bearer <token>', () async {
    Session.iniciar(id: 1, u: 'admin', r: 'administrador', tokenSesion: 'abc123');
    String? cabecera;
    final cliente = ClienteConToken(MockClient((req) async {
      cabecera = req.headers['Authorization'];
      return http.Response('{}', 200);
    }));
    await cliente.get(Uri.parse('http://api/productos'));
    expect(cabecera, 'Bearer abc123');
  });

  test('un 401 con sesion abierta la cierra', () async {
    Session.iniciar(id: 1, u: 'admin', r: 'administrador', tokenSesion: 'vencido');
    final cliente = ClienteConToken(MockClient((_) async => http.Response('{}', 401)));
    await cliente.get(Uri.parse('http://api/productos'));
    expect(Session.iniciada, isFalse);
    expect(Session.token, isNull);
  });

  test('un 401 sin sesion (clave mala en el login) no hace nada raro', () async {
    var navegado = false;
    Navegacion.login = () {
      navegado = true;
      throw StateError('no debia abrirse');
    };
    final cliente = ClienteConToken(MockClient((_) async => http.Response('{}', 401)));
    final r = await cliente.post(Uri.parse('http://api/auth/login'), body: '{}');
    expect(r.statusCode, 401);
    expect(navegado, isFalse);
  });
}
