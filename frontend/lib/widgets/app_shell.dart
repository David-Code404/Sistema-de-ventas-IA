import 'package:flutter/material.dart';

import '../screens/catalogo_screen.dart';
import '../screens/categorias_crud_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/historial_ventas_screen.dart';
import '../screens/inventario_screen.dart';
import '../screens/pedidos_pendientes_screen.dart';
import '../models/pedidos_monitor.dart';
import '../models/session.dart';
import '../screens/login_screen.dart';
import '../theme/theme_controller.dart';
import 'cambiar_password_dialog.dart';
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
    // Sondeo de pedidos para el contador (solo admin y cajero; no repite si ya corre)
    PedidosMonitor.instance.iniciar(apiBase);
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
    // Se redibuja cuando cambia el contador de pedidos
    return ListenableBuilder(
      listenable: PedidosMonitor.instance,
      builder: (context, _) => _barra(context),
    );
  }

  Widget _barra(BuildContext context) {
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
                contador: PedidosMonitor.instance.pendientes,
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
              // En celular no hay sidebar: cuenta, modo y cerrar sesion van aqui
              _Btn(
                icon: Icons.account_circle_outlined,
                label: 'Cuenta',
                active: false,
                onTap: () => _abrirCuenta(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirCuenta(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceAlt,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_outline, color: AppColors.textMuted),
              title: Text(Session.username ?? 'Usuario',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(Session.esAdmin ? 'Administrador' : 'Cajero',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            Divider(color: AppColors.border, height: 1),
            ListTile(
              leading: Icon(Icons.lock_reset_rounded, color: AppColors.textSecondary),
              title: Text('Cambiar contraseña'),
              onTap: () {
                Navigator.pop(ctx);
                mostrarCambiarPassword(context, apiBase: apiBase);
              },
            ),
            ListTile(
              leading: Icon(
                  ThemeController.instance.isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  color: AppColors.textSecondary),
              title: Text(ThemeController.instance.isDark
                  ? 'Cambiar a modo claro'
                  : 'Cambiar a modo oscuro'),
              onTap: () {
                Navigator.pop(ctx);
                ThemeController.instance.toggle();
              },
            ),
            ListTile(
              leading: Icon(Icons.logout_rounded, color: AppColors.danger),
              title: Text('Cerrar sesion', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                PedidosMonitor.instance.detener();
                Session.cerrar();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => LoginScreen(apiBase: apiBase)),
                  (_) => false,
                );
              },
            ),
            SizedBox(height: 8),
          ],
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
  final int contador;

  const _Btn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.contador = 0,
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
            Badge(
              isLabelVisible: contador > 0,
              backgroundColor: AppColors.warning,
              textColor: AppColors.accentOnAccent,
              label: Text(contador > 99 ? '99+' : '$contador'),
              child: Icon(icon, size: 20, color: color),
            ),
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