import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Sesion del usuario activo. Vive en memoria y tambien se guarda en el navegador
/// (shared_preferences), para que al actualizar la pagina no se pierda y no pida iniciar sesion otra vez.
class Session {
  Session._();

  static int?    usuarioId;
  static String? username;
  static String? rol;

  /// Ficha del cliente (nombre, documento, telefono...) si el rol es cliente.
  static Map<String, dynamic>? cliente;

  static bool get esAdmin   => rol == 'administrador';
  static bool get esCajero  => rol == 'cajero';
  static bool get esCliente => rol == 'cliente';
  static bool get iniciada  => rol != null;

  static const String _clave = 'sesion_activa';

  /// Recupera la sesion guardada (si la hay). Se llama una vez al abrir la app.
  static Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_clave);
      if (texto == null) return;
      final datos = jsonDecode(texto);
      if (datos is! Map) return;
      final id = datos['id'];
      final u = datos['u'];
      final r = datos['r'];
      if (id is! int || u is! String || r is! String) return;
      if (!const ['administrador', 'cajero', 'cliente'].contains(r)) return;
      usuarioId = id;
      username  = u;
      rol       = r;
      final c = datos['c'];
      cliente   = c is Map ? Map<String, dynamic>.from(c) : null;
    } catch (_) {
      // sesion danada o sin almacenamiento: se empieza sin sesion
    }
  }

  static Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave, jsonEncode({'id': usuarioId, 'u': username, 'r': rol, 'c': cliente}));
    } catch (_) {}
  }

  static Future<void> _borrar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_clave);
    } catch (_) {}
  }

  static void iniciar({
    required int id,
    required String u,
    required String r,
    Map<String, dynamic>? datosCliente,
  }) {
    usuarioId = id;
    username  = u;
    rol       = r;
    cliente   = datosCliente;
    _guardar();
  }

  static void cerrar() {
    usuarioId = null;
    username  = null;
    rol       = null;
    cliente   = null;
    _borrar();
  }
}
