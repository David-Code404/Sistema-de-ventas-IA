import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';

class EstadoPedidoScreen extends StatefulWidget {
  final String apiBase;
  EstadoPedidoScreen({super.key, required this.apiBase});

  @override
  State<EstadoPedidoScreen> createState() => _EstadoPedidoScreenState();
}

class _EstadoPedidoScreenState extends State<EstadoPedidoScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool    _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final uid = Session.usuarioId;
    if (uid == null) {
      setState(() { _cargando = false; _error = 'Sin sesión activa.'; });
      return;
    }
    setState(() { _cargando = true; _error = null; });
    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBase}/ventas/cliente/$uid'),
      );
      if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');
      final lista = jsonDecode(resp.body) as List<dynamic>;
      setState(() {
        _pedidos  = lista.cast<Map<String, dynamic>>();
        _cargando = false;
      });
    } catch (e) {
      setState(() { _cargando = false; _error = 'No se pudo cargar: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BoundedContent(
      maxWidth: 700,
      child: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: _cargar,
        child: _buildContenido(),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return ListView(children: [
        SizedBox(height: 80),
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
          SizedBox(height: 12),
          TextButton.icon(
            onPressed: _cargar,
            icon: Icon(Icons.refresh, size: 16),
            label: Text('Reintentar'),
          ),
        ])),
      ]);
    }

    if (_pedidos.isEmpty) {
      return ListView(children: [
        SizedBox(height: 80),
        Icon(Icons.receipt_long_outlined,
            color: AppColors.textMuted, size: 52),
        SizedBox(height: 16),
        Text('Aún no tienes pedidos',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text('Tus compras aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]);
    }

    final activo    = _pedidos.where((p) => p['estado'] == 'en_progreso').toList();
    final historial = _pedidos.where((p) => p['estado'] != 'en_progreso').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (activo.isNotEmpty) ...[
          _seccion('PEDIDO ACTUAL'),
          SizedBox(height: 8),
          ...activo.map((p) => _buildTarjeta(p, destacado: true)),
          SizedBox(height: 20),
        ],
        if (historial.isNotEmpty) ...[
          _seccion('HISTORIAL'),
          SizedBox(height: 8),
          ...historial.map((p) => _buildTarjeta(p, destacado: false)),
        ],
      ],
    );
  }

  Widget _seccion(String texto) => Text(texto,
      style: TextStyle(color: AppColors.textMuted, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.5));

  Widget _buildTarjeta(Map<String, dynamic> p, {required bool destacado}) {
    final enProgreso  = p['estado'] == 'en_progreso';
    final total       = double.tryParse(p['total'].toString()) ?? 0;
    final fecha       = DateTime.tryParse(p['fecha']?.toString() ?? '');
    final resumen     = (p['resumen_productos'] as String?)?.trim() ?? 'Sin productos';
    final cantidad    = p['cantidad_productos'] ?? 0;
    final metodo      = p['metodo_pago'] as String?;

    final estadoColor = enProgreso ? Color(0xFFF59E0B) : AppColors.accent;
    final estadoLabel = enProgreso ? 'En progreso' : 'Finalizado';
    final estadoIcon  = enProgreso
        ? Icons.hourglass_top_rounded
        : Icons.check_circle_outline_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: destacado
              ? estadoColor.withValues(alpha: 0.45)
              : AppColors.border,
          width: destacado ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Encabezado
          Row(children: [
            Icon(estadoIcon, color: estadoColor, size: 16),
            SizedBox(width: 6),
            Text('Pedido #${p['id']}',
                style: TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700, fontSize: 14)),
            Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: estadoColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: estadoColor.withValues(alpha: 0.35)),
              ),
              child: Text(estadoLabel,
                  style: TextStyle(color: estadoColor,
                      fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
          SizedBox(height: 10),
          Divider(color: AppColors.border, height: 1),
          SizedBox(height: 10),

          // Productos
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.shopping_bag_outlined,
                color: AppColors.textMuted, size: 14),
            SizedBox(width: 6),
            Expanded(
              child: Text(resumen,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
            ),
          ]),
          SizedBox(height: 6),

          // Fecha y cantidad
          Row(children: [
            Icon(Icons.calendar_today_outlined,
                color: AppColors.textMuted, size: 13),
            SizedBox(width: 5),
            Text(
              fecha != null ? _formatearFecha(fecha) : '—',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            SizedBox(width: 12),
            Icon(Icons.inventory_2_outlined,
                color: AppColors.textMuted, size: 13),
            SizedBox(width: 5),
            Text('$cantidad producto${cantidad == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),

          if (metodo != null && !enProgreso) ...[
            SizedBox(height: 6),
            Row(children: [
              Icon(Icons.payment_outlined,
                  color: AppColors.textMuted, size: 13),
              SizedBox(width: 5),
              Text(_labelMetodo(metodo),
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ]),
          ],

          SizedBox(height: 10),
          Divider(color: AppColors.border, height: 1),
          SizedBox(height: 10),

          // Total
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total',
                style: TextStyle(color: AppColors.textSecondary,
                    fontSize: 13, fontWeight: FontWeight.w500)),
            Text('Bs. ${total.toStringAsFixed(2)}',
                style: TextStyle(color: AppColors.accent,
                    fontWeight: FontWeight.w800, fontSize: 18)),
          ]),
        ]),
      ),
    );
  }

  String _formatearFecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}  ${dos(f.hour)}:${dos(f.minute)}';
  }

  String _labelMetodo(String m) {
    switch (m) {
      case 'efectivo': return 'Pago en efectivo';
      case 'tarjeta':  return 'Pago con tarjeta';
      case 'qr':       return 'Pago por QR';
      default:         return m;
    }
  }
}