import 'package:flutter/material.dart';

import '../screens/catalogo_screen.dart';
import '../screens/categorias_crud_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/historial_ventas_screen.dart';
import '../screens/inventario_screen.dart';
import '../screens/pedidos_pendientes_screen.dart';
import '../theme/app_colors.dart';
import 'app_sidebar.dart';

const _anchoMovil = 700.0;

class AppShell extends StatelessWidget {
  final AppSection current;
  final String apiBase;
  final Widget child;

  AppShell({
    super.key,
    required this.current,
    required this.apiBase,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final movil = constraints.maxWidth < _anchoMovil;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: movil
              ? child
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSidebar(current: current, apiBase: apiBase),
                    Expanded(child: child),
                  ],
                ),
          bottomNavigationBar:
              movil ? _BarraInferior(current: current, apiBase: apiBase) : null,
        );
      },
    );
  }
}

class _BarraInferior extends StatelessWidget {
  final AppSection current;
  final String apiBase;

  const _BarraInferior({required this.current, required this.apiBase});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              _Btn(
                icon: Icons.space_dashboard_outlined,
                label: 'Dashboard',
                active: current == AppSection.dashboard,
                onTap: () => _ir(context, DashboardScreen()),
              ),
              _Btn(
                icon: Icons.receipt_long_outlined,
                label: 'Ventas',
                active: current == AppSection.ventas,
                onTap: () => _ir(context, HistorialVentasScreen()),
              ),
              _Btn(
                icon: Icons.shopping_bag_outlined,
                label: 'Pedidos',
                active: current == AppSection.pedidos,
                onTap: () => _ir(context, PedidosPendientesScreen(apiBase: apiBase)),
              ),
              _Btn(
                icon: Icons.category_outlined,
                label: 'Categorias',
                active: current == AppSection.categorias,
                onTap: () => _ir(context, CategoriasCrudScreen(apiBase: apiBase)),
              ),
              _Btn(
                icon: Icons.inventory_2_outlined,
                label: 'Catalogo',
                active: current == AppSection.catalogo,
                onTap: () => _ir(context, CatalogoScreen(apiBase: apiBase)),
              ),
              _Btn(
                icon: Icons.warehouse_outlined,
                label: 'Inventario',
                active: current == AppSection.inventario,
                onTap: () => _ir(context, InventarioScreen(apiBase: apiBase)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ir(BuildContext context, Widget pantalla) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => pantalla));
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: active ? null : onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}