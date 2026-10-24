import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';

class DetalleVentaScreen extends StatefulWidget {
  final Map<String, dynamic> venta;
  final String apiBase;

  DetalleVentaScreen({super.key, required this.venta, required this.apiBase});

  @override
  State<DetalleVentaScreen> createState() => _DetalleVentaScreenState();
}

class _DetalleVentaScreenState extends State<DetalleVentaScreen> {
  List<Map<String, dynamic>> _items = [];
  double _total     = 0;
  bool   _cargando  = true;
  bool   _descargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDetalle();
  }

  Future<void> _cargarDetalle() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final ventaId = widget.venta['id'];
      final resp = await http.get(
          Uri.parse('${widget.apiBase}/ventas/$ventaId/carrito'));
      if (resp.statusCode != 200) {
        throw Exception('El backend respondio ${resp.statusCode}');
      }
      final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
      final itemsJson = cuerpo['items'] as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _items    = itemsJson.cast<Map<String, dynamic>>();
        _total    = double.tryParse(cuerpo['total'].toString()) ?? 0;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo cargar el detalle: $e'; });
    }
  }

  // ── Permiso de descarga ───────────────────────────────────
  bool get _puedeDescargar {
    // Admin y cajero siempre pueden
    if (Session.esAdmin || Session.esCajero) return true;
    // Cliente: solo si la venta le pertenece
    if (Session.esCliente) {
      final propietario = widget.venta['cliente_usuario_id'];
      return propietario != null && propietario == Session.usuarioId;
    }
    return false;
  }

  // ── Descarga PDF ──────────────────────────────────────────
  Future<void> _descargarPdf() async {
    setState(() => _descargando = true);
    try {
      final ventaId   = widget.venta['id'];
      final usuarioId = Session.usuarioId ?? 0;
      final rol       = Session.rol ?? '';
      final cajero    = Session.username ?? '';

      final url = Uri.parse(
        '${widget.apiBase}/ventas/$ventaId/comprobante.pdf'
        '?usuario_id=$usuarioId&rol=$rol&atendido_por=$cajero',
      );

      final resp = await http.get(url);
      if (resp.statusCode == 403) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No tienes permiso para descargar este comprobante.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        return;
      }
      if (resp.statusCode != 200) {
        throw Exception('Error ${resp.statusCode}');
      }

      // Descargar en el navegador
      final blob = html.Blob([resp.bodyBytes], 'application/pdf');
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: blobUrl)
        ..setAttribute('download', 'comprobante_$ventaId.pdf')
        ..click();
      html.Url.revokeObjectUrl(blobUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comprobante descargado.'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo descargar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _descargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venta #${widget.venta['id']}'),
        actions: [
          if (_puedeDescargar)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _descargando
                  ? Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Descargar comprobante PDF',
                      icon: Icon(Icons.download_outlined),
                      color: AppColors.accent,
                      onPressed: _descargarPdf,
                    ),
            ),
        ],
      ),
      body: BoundedContent(child: _buildContenido()),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 12),
              TextButton.icon(
                onPressed: _cargarDetalle,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildEncabezado(),
        ),
        SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('PRODUCTOS',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1)),
        ),
        SizedBox(height: 8),
        Expanded(child: _buildLista()),
        _buildTotal(),
      ],
    );
  }

  Widget _buildEncabezado() {
    final estado       = (widget.venta['estado'] ?? '').toString();
    final esFinalizada = estado == 'finalizada';
    final fecha        = widget.venta['fecha']?.toString();
    final color        = esFinalizada ? AppColors.accent : AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              esFinalizada ? Icons.check_circle_outline : Icons.hourglass_bottom,
              color: color, size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  esFinalizada ? 'Finalizada' : 'En progreso',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (fecha != null) ...[
                  SizedBox(height: 2),
                  Text(fecha,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ],
            ),
          ),
          // Indicador de permiso para cliente
          if (Session.esCliente && !_puedeDescargar)
            Tooltip(
              message: 'Este comprobante no pertenece a tu cuenta',
              child: Icon(Icons.lock_outline, color: AppColors.textMuted, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildLista() {
    if (_items.isEmpty) {
      return Center(
        child: Text('Esta venta no tiene productos.',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _items.length,
      separatorBuilder: (_, __) => SizedBox(height: 10),
      itemBuilder: (context, i) {
        final item          = _items[i];
        final cantidad      = item['cantidad'];
        final precioUnit    = double.tryParse(item['precio_unitario'].toString()) ?? 0;
        final subtotal      = double.tryParse(item['subtotal'].toString())
            ?? (precioUnit * (cantidad as num));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['nombre'].toString(),
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    SizedBox(height: 2),
                    Text('$cantidad × S/ ${precioUnit.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Text('S/ ${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTotal() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('TOTAL',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          Text('S/ ${_total.toStringAsFixed(2)}',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}