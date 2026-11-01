import 'package:http/http.dart' as http;

import 'descarga.dart';

/// Descarga un PDF enviando el token de sesion (un enlace directo no lo envia).
Future<bool> descargarPdfConSesion(String url, String nombre) async {
  try {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return false;
    descargarBytes(resp.bodyBytes, nombre);
    return true;
  } catch (_) {
    return false;
  }
}
