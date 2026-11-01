import 'package:flutter/material.dart';

/// Pantallas de entrada que la tienda en linea necesita abrir (login e
/// inicio del cliente). Se registran en main.dart, asi las pantallas del
/// carrito y del pedido no importan las del personal (que usan dart:html) y
/// se pueden probar fuera del navegador.
class Navegacion {
  Navegacion._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Vuelve al login cuando el servidor rechaza el token (sesion vencida).
  static void sesionVencida() {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => login()),
      (_) => false,
    );
  }

  static Widget Function() login = () => const SizedBox.shrink();
  static Widget Function() inicioCliente = () => const SizedBox.shrink();
}
