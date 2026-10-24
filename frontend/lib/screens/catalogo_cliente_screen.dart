// TEMPORAL (solo local, borrar): reemplaza el archivo que falta en main.
import 'package:flutter/material.dart';

import 'cliente_productos_screen.dart';

class CatalogoClienteScreen extends StatelessWidget {
  final String apiBase;

  CatalogoClienteScreen({super.key, required this.apiBase});

  @override
  Widget build(BuildContext context) => ClienteProductosScreen(apiBase: apiBase);
}
