import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Etiqueta, color e icono de cada estado de ventas.estado, para que todas
/// las pantallas muestren lo mismo.
///   en_progreso : venta en caja (POS) sin cerrar
///   pendiente   : pedido en linea del cliente, esperando preparacion
///   listo       : pedido preparado, listo para recoger (stock ya descontado)
///   finalizada  : venta cobrada
class EstadoVenta {
  final String etiqueta;
  final Color color;
  final IconData icono;

  const EstadoVenta(this.etiqueta, this.color, this.icono);

  static const _celeste = Color(0xFF38BDF8);

  static EstadoVenta de(String? estado) {
    switch (estado) {
      case 'pendiente':
        return EstadoVenta('Pendiente', AppColors.warning, Icons.schedule_rounded);
      case 'listo':
        return const EstadoVenta('Listo para recoger', _celeste, Icons.shopping_bag_outlined);
      case 'finalizada':
        return EstadoVenta('Finalizada', AppColors.accent, Icons.check_circle_outline);
      case 'en_progreso':
      default:
        return EstadoVenta('En progreso', AppColors.warning, Icons.hourglass_bottom);
    }
  }
}
