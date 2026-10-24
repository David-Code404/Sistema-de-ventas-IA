import 'package:flutter/material.dart';
import '../screens/historial_ventas_screen.dart';

/// CajeroShell — inicia en el historial de ventas, que tiene el botón
/// "Nueva venta" para acceder a la caja registradora.
class CajeroShell extends StatelessWidget {
  final String apiBase;

  CajeroShell({super.key, required this.apiBase});

  @override
  Widget build(BuildContext context) => HistorialVentasScreen();
}