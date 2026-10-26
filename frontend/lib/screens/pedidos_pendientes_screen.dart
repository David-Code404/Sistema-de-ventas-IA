import 'package:flutter/material.dart';

import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/pedidos_panel.dart';

/// Pedidos en linea de los clientes (pendientes y listos para recoger),
/// visible para administrador y cajero. El contenido esta en PedidosPanel.
class PedidosPendientesScreen extends StatelessWidget {
  final String apiBase;

  const PedidosPendientesScreen({super.key, required this.apiBase});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.pedidos,
      apiBase: apiBase,
      child: PedidosPanel(apiBase: apiBase),
    );
  }
}
