import 'package:flutter/material.dart';

import '../models/pedidos_monitor.dart';
import '../models/session.dart';
import '../screens/agregar_producto_screen.dart';
import '../screens/catalogo_screen.dart';
import '../screens/categorias_crud_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/historial_ventas_screen.dart';
import '../screens/inventario_screen.dart';
import '../screens/login_screen.dart';
import '../screens/pedidos_pendientes_screen.dart';
import '../screens/usuarios_screen.dart';
import '../theme/app_colors.dart';
import 'cambiar_password_dialog.dart';
import '../theme/theme_controller.dart';

enum AppSection {
  dashboard,
  ventas,
  pedidos,
  categorias,
  catalogo,
  inventario,
  usuarios,
  agregarProducto,
}

class AppSidebar extends StatelessWidget {
  final AppSection current;
  final String apiBase;

  AppSidebar({super.key, required this.current, required this.apiBase});

  @override
  Widget build(BuildContext context) {
    final esAdmin  = Session.esAdmin;

    return Container(
      width: 220,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera usuario
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: _colorRol.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_iconoRol, color: _colorRol, size: 17),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Session.username ?? 'Usuario',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                      Text(
                        _etiquetaRol,
                        style: TextStyle(
                            color: _colorRol,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.border, height: 1),
          SizedBox(height: 12),

          // Menu desplazable: si la ventana es baja, el toggle y 'Cerrar sesion' no se desbordan
          Expanded(child: SingleChildScrollView(child: Column(children: [
          // Dashboard — solo Admin
          if (esAdmin)
            _NavItem(
              icon: Icons.space_dashboard_outlined,
              label: 'Dashboard',
              active: current == AppSection.dashboard,
              onTap: () => _ir(context, DashboardScreen()),
            ),

          // Ventas
          _NavItem(
            icon: Icons.receipt_long_outlined,
            label: 'Ventas',
            active: current == AppSection.ventas,
            onTap: () => _ir(context, HistorialVentasScreen()),
          ),

          // Pedidos de clientes — Admin y Cajero (contador de pedidos pendientes)
          ListenableBuilder(
            listenable: PedidosMonitor.instance,
            builder: (context, _) => _NavItem(
              icon: Icons.shopping_bag_outlined,
              label: 'Pedidos',
              contador: PedidosMonitor.instance.pendientes,
              active: current == AppSection.pedidos,
              onTap: () => _ir(context, PedidosPendientesScreen(apiBase: apiBase)),
            ),
          ),

          // Categorias
          _NavItem(
            icon: Icons.category_outlined,
            label: 'Categorias',
            active: current == AppSection.categorias,
            onTap: () => _ir(context, CategoriasCrudScreen(apiBase: apiBase)),
          ),

          // Catalogo
          _NavItem(
            icon: Icons.inventory_2_outlined,
            label: 'Catalogo',
            active: current == AppSection.catalogo,
            onTap: () => _ir(context, CatalogoScreen(apiBase: apiBase)),
          ),

          // Inventario
          _NavItem(
            icon: Icons.warehouse_outlined,
            label: 'Inventario',
            active: current == AppSection.inventario,
            onTap: () => _ir(context, InventarioScreen(apiBase: apiBase)),
          ),

          // Usuarios — solo Admin
          if (esAdmin)
            _NavItem(
              icon: Icons.group_outlined,
              label: 'Usuarios',
              active: current == AppSection.usuarios,
              onTap: () => _ir(context, UsuariosScreen(apiBase: apiBase)),
            ),

          // Productos — solo Admin
          if (esAdmin) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Divider(color: AppColors.border),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Text(
                'PRODUCTOS',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
            ),
            SizedBox(height: 4),
            _NavItem(
              icon: Icons.add_box_outlined,
              label: 'Agregar producto',
              active: current == AppSection.agregarProducto,
              onTap: () => _ir(context, AgregarProductoScreen(apiBase: apiBase)),
            ),
          ],

          ]))),
          Divider(color: AppColors.border, height: 1),
          SizedBox(height: 4),

          // Cambiar contraseña (confirmando la actual)
          _NavItem(
            icon: Icons.lock_reset_rounded,
            label: 'Cambiar contraseña',
            active: false,
            onTap: () => mostrarCambiarPassword(context, apiBase: apiBase),
          ),

          // Toggle modo claro / oscuro
          ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeController.instance,
            builder: (_, mode, __) {
              final dark = mode == ThemeMode.dark;
              return InkWell(
                onTap: ThemeController.instance.toggle,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(width: 10),
                    Text(
                      dark ? 'Modo oscuro' : 'Modo claro',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500),
                    ),
                    Spacer(),
                    IgnorePointer(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: 40,
                        height: 22,
                        decoration: BoxDecoration(
                          color: dark
                              ? AppColors.accent.withValues(alpha: 0.25)
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: dark
                                ? AppColors.accent.withValues(alpha: 0.5)
                                : AppColors.accent,
                          ),
                        ),
                        child: AnimatedAlign(
                          duration: Duration(milliseconds: 200),
                          alignment: dark
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              );
            },
          ),

          Divider(color: AppColors.border, height: 1),

          // Cerrar sesion
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => _cerrarSesion(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded,
                          size: 17,
                          color: AppColors.danger.withValues(alpha: 0.8)),
                      SizedBox(width: 11),
                      Text(
                        'Cerrar sesion',
                        style: TextStyle(
                          color: AppColors.danger.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 4),
        ],
      ),
    );
  }

  Color get _colorRol {
    if (Session.esAdmin)  return AppColors.accent;
    if (Session.esCajero) return AppColors.warning;
    return AppColors.info;
  }

  IconData get _iconoRol {
    if (Session.esAdmin)  return Icons.admin_panel_settings_outlined;
    if (Session.esCajero) return Icons.point_of_sale_outlined;
    return Icons.person_outline_rounded;
  }

  String get _etiquetaRol {
    if (Session.esAdmin)  return 'Administrador';
    if (Session.esCajero) return 'Cajero';
    return 'Cliente';
  }

  void _ir(BuildContext context, Widget pantalla) {
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => pantalla));
  }

  void _cerrarSesion(BuildContext context) {
    PedidosMonitor.instance.detener();
    Session.cerrar();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(apiBase: apiBase)),
      (_) => false,
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int contador;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.contador = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: active
            ? AppColors.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: active ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: active
                        ? AppColors.accent
                        : AppColors.textSecondary),
                SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: active
                        ? AppColors.accent
                        : AppColors.textSecondary,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                if (contador > 0) ...[
                  Spacer(),
                  Tooltip(
                    message: '$contador pedido(s) pendiente(s) por preparar',
                    child: Container(
                      constraints: BoxConstraints(minWidth: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(contador > 99 ? '99+' : '$contador',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.accentOnAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}