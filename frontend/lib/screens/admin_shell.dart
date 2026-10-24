import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';

/// AdminShell — redirige al DashboardScreen que ya tiene su propio
/// sidebar con todas las secciones del administrador y cerrar sesion.
class AdminShell extends StatelessWidget {
  final String apiBase;

  AdminShell({super.key, required this.apiBase});

  @override
  Widget build(BuildContext context) => DashboardScreen();
}