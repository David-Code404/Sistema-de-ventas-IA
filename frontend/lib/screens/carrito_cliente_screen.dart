import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/carrito_cliente.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/boton_carrito.dart';
import '../widgets/bounded_content.dart';
import '../navegacion.dart';
import 'confirmar_pedido_screen.dart';

String formatoBs(double v) => 'Bs ${v.toStringAsFixed(2)}';

/// Vuelve a pedir el stock y los precios (GET /inventario) y ajusta el
/// carrito. Devuelve los avisos para el cliente. Lanza excepcion si no hay
/// conexion.
Future<List<String>> sincronizarCarrito(String apiBase) async {
  final resp = await http
      .get(Uri.parse('$apiBase/inventario'))
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) throw Exception('Servidor: ${resp.statusCode}');
  final lista = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
  return CarritoCliente.instance.sincronizar(lista);
}

/// Carrito del cliente: productos, cantidades editables, subtotales y total.
class CarritoClienteScreen extends StatefulWidget {
  final String apiBase;

  const CarritoClienteScreen({super.key, required this.apiBase});

  @override
  State<CarritoClienteScreen> createState() => _CarritoClienteScreenState();
}

class _CarritoClienteScreenState extends State<CarritoClienteScreen> {
  final _carrito = CarritoCliente.instance;
  List<String> _avisos = [];
  bool _sinConexion = false;

  @override
  void initState() {
    super.initState();
    _actualizarStock();
  }

  Future<void> _actualizarStock() async {
    if (_carrito.vacio) return;
    try {
      final avisos = await sincronizarCarrito(widget.apiBase);
      if (!mounted) return;
      setState(() {
        _avisos = avisos;
        _sinConexion = false;
      });
    } catch (_) {
      if (mounted) setState(() => _sinConexion = true);
    }
  }

  Future<void> _continuar() async {
    if (!Session.esCliente) {
      final iniciar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: Text('Inicia sesion para continuar'),
          content: Text(
              'Para confirmar tu pedido inicia sesion o crea tu cuenta. '
              'Tu carrito se guarda mientras tanto.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Ahora no')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Iniciar sesion')),
          ],
        ),
      );
      if (iniciar == true && mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => Navegacion.login()));
      }
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ConfirmarPedidoScreen(apiBase: widget.apiBase)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _carrito,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            title: Text(_carrito.vacio
                ? 'Mi carrito'
                : 'Mi carrito (${_carrito.unidades})'),
            actions: [
              if (!_carrito.vacio)
                TextButton.icon(
                  onPressed: _confirmarVaciar,
                  icon: Icon(Icons.delete_sweep_outlined,
                      size: 17, color: AppColors.danger),
                  label: Text('Vaciar',
                      style: TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              SizedBox(width: 8),
            ],
          ),
          body: _carrito.vacio ? _vacio() : _lista(),
          bottomNavigationBar: _carrito.vacio ? null : _barraTotal(),
        );
      },
    );
  }

  Future<void> _confirmarVaciar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text('Vaciar carrito'),
        content: Text('Se quitaran todos los productos del carrito.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Vaciar')),
        ],
      ),
    );
    if (ok == true) _carrito.vaciar();
  }

  Widget _vacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.shopping_cart_outlined,
                  color: AppColors.accent, size: 34),
            ),
            SizedBox(height: 16),
            Text('Tu carrito esta vacio',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text('Agrega productos desde el catalogo para hacer tu pedido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.storefront_outlined, size: 18),
              label: Text('Volver al catalogo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    return BoundedContent(
      maxWidth: 760,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_sinConexion)
            _aviso(
              'No se pudo actualizar el stock. Revisa tu conexion; '
              'al confirmar el pedido se vuelve a verificar.',
              AppColors.warning,
              Icons.wifi_off_rounded,
            ),
          for (final a in _avisos)
            _aviso(a, AppColors.warning, Icons.info_outline_rounded),
          for (final item in _carrito.items) _filaItem(item),
        ],
      ),
    );
  }

  Widget _aviso(String texto, Color color, IconData icono) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          SizedBox(width: 8),
          Expanded(
              child: Text(texto,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5))),
        ],
      ),
    );
  }

  Widget _filaItem(ItemCarrito item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ImagenProducto(apiBase: widget.apiBase, productoId: item.productoId),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('${formatoBs(item.precio)} c/u',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Quitar del carrito',
                onPressed: () => _carrito.quitar(item.productoId),
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: AppColors.danger),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              SelectorCantidad(
                cantidad: item.cantidad,
                maximo: item.stock,
                onCambio: (n) => _carrito.cambiarCantidad(item.productoId, n),
              ),
              SizedBox(width: 10),
              if (item.cantidad >= item.stock)
                Flexible(
                  child: Text('Maximo disponible',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.warning, fontSize: 11.5)),
                ),
              Spacer(),
              Text(formatoBs(item.subtotal),
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _barraTotal() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('TOTAL',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(formatoBs(_carrito.total),
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _continuar,
                    icon: Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text('Continuar'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de cantidad  [-] N [+]  limitado entre 1 y [maximo].
class SelectorCantidad extends StatelessWidget {
  final int cantidad;
  final int maximo;
  final ValueChanged<int> onCambio;

  const SelectorCantidad({
    super.key,
    required this.cantidad,
    required this.maximo,
    required this.onCambio,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, String ayuda, VoidCallback? accion) => InkWell(
          onTap: accion,
          borderRadius: BorderRadius.circular(8),
          child: Tooltip(
            message: ayuda,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icono,
                  size: 16,
                  color: accion == null ? AppColors.textMuted : AppColors.accent),
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(Icons.remove_rounded, 'Quitar uno',
              cantidad > 1 ? () => onCambio(cantidad - 1) : null),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 28),
            child: Text('$cantidad',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
          boton(Icons.add_rounded, 'Agregar uno',
              cantidad < maximo ? () => onCambio(cantidad + 1) : null),
        ],
      ),
    );
  }
}
