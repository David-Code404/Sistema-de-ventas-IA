import 'package:flutter/material.dart';

import '../models/session.dart';
import '../screens/login_screen.dart';
import '../screens/estado_pedido_screen.dart';
import '../theme/app_colors.dart';
import 'catalogo_cliente_screen.dart';

class ClienteShell extends StatefulWidget {
  final String apiBase;
  ClienteShell({super.key, required this.apiBase});

  @override
  State<ClienteShell> createState() => _ClienteShellState();
}

class _ClienteShellState extends State<ClienteShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _cerrarSesion() {
    Session.cerrar();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(apiBase: widget.apiBase)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: Color(0xFF38BDF8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.person_outline_rounded,
                color: Color(0xFF38BDF8), size: 15),
          ),
          SizedBox(width: 8),
          Text(Session.username ?? 'Cliente',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(width: 6),
          Text('— Cliente',
              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: _cerrarSesion,
            icon: Icon(Icons.logout_rounded,
                size: 15, color: AppColors.danger.withValues(alpha: 0.8)),
            label: Text('Salir',
                style: TextStyle(
                    color: AppColors.danger.withValues(alpha: 0.8),
                    fontSize: 13)),
          ),
          SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.accent,
          indicatorWeight: 2.5,
          labelStyle: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          tabs: [
            Tab(icon: Icon(Icons.storefront_outlined, size: 18),
                text: 'Catálogo'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 18),
                text: 'Mis Pedidos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          CatalogoClienteScreen(apiBase: widget.apiBase),
          EstadoPedidoScreen(apiBase: widget.apiBase),
        ],
      ),
    );
  }
}