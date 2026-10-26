import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'session.dart';

/// Consulta cada [intervalo] cuantos pedidos de clientes hay pendientes y listos
/// (GET /pedidos/resumen) mientras haya un administrador o cajero con sesion.
/// Alimenta el contador del boton "Pedidos" (solo pendientes: los que el
/// cajero aun debe preparar) y avisa a la pantalla de pedidos
/// cuando algo cambia, para que se actualice sin recargar.
class PedidosMonitor extends ChangeNotifier {
  PedidosMonitor._();

  static final instance = PedidosMonitor._();

  static const intervalo = Duration(seconds: 10);

  Timer? _timer;
  String? _apiBase;

  int pendientes = 0;
  int listos = 0;
  int ultimoPendienteId = 0;

  /// Sube cada vez que cambia algo; la pantalla de pedidos recarga al verlo.
  int version = 0;

  int get sinFinalizar => pendientes + listos;

  static bool get _esPersonal => Session.esAdmin || Session.esCajero;

  /// Arranca el sondeo (no hace nada si ya esta corriendo o no hay personal).
  void iniciar(String apiBase) {
    if (!_esPersonal) return;
    if (_timer != null && _apiBase == apiBase) return;
    _apiBase = apiBase;
    _timer?.cancel();
    _timer = Timer.periodic(intervalo, (_) => actualizar());
    actualizar();
  }

  /// Detiene el sondeo y limpia los contadores (al cerrar sesion).
  void detener() {
    _timer?.cancel();
    _timer = null;
    _apiBase = null;
    pendientes = listos = ultimoPendienteId = 0;
    notifyListeners();
  }

  Future<void> actualizar() async {
    final api = _apiBase;
    if (api == null) return;
    if (!_esPersonal) {
      detener();
      return;
    }
    try {
      final resp = await http
          .get(Uri.parse('$api/pedidos/resumen'))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final r = jsonDecode(resp.body) as Map<String, dynamic>;
      final p = (r['pendientes'] as num).toInt();
      final l = (r['listos'] as num).toInt();
      final u = (r['ultimo_pendiente_id'] as num).toInt();
      if (p == pendientes && l == listos && u == ultimoPendienteId) return;
      pendientes = p;
      listos = l;
      ultimoPendienteId = u;
      version++;
      notifyListeners();
    } catch (_) {
      // Sin conexion: se reintenta en el siguiente intervalo
    }
  }
}
