import 'package:http/http.dart' as http;

import '../navegacion.dart';
import 'session.dart';

/// Cliente HTTP de toda la app: agrega el token de sesion a cada peticion y, si el
/// servidor responde 401 con una sesion abierta (token vencido), vuelve al login.
class ClienteConToken extends http.BaseClient {
  final http.Client _interno;
  ClienteConToken(this._interno);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = Session.token;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final resp = await _interno.send(request);
    if (resp.statusCode == 401 && token != null && Session.token == token) {
      Session.cerrar();
      Navegacion.sesionVencida();
    }
    return resp;
  }
}
