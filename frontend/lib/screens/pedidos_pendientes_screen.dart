import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

/// Pedidos que los clientes registraron con estado "pendiente".
/// Visible para administrador y cajero.
class PedidosPendientesScreen extends StatefulWidget {
  final String apiBase;

  const PedidosPendientesScreen({super.key, required this.apiBase});

  @override
  State<PedidosPendientesScreen> createState() => _PedidosPendientesScreenState();
}

class _PedidosPendientesScreenState extends State<PedidosPendientesScreen> {
  List<Map<String, dynamic>> _pedidos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp =
          await http.get(Uri.parse('${widget.apiBase}/pedidos/pendientes'));
      if (resp.statusCode != 200) throw Exception('Backend: ${resp.statusCode}');
      final lista = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _pedidos = lista.cast<Map<String, dynamic>>();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los pedidos: $e';
      });
    }
  }

  String _dos(int n) => n.toString().padLeft(2, '0');

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '-';
    return '${_dos(d.day)}/${_dos(d.month)}/${d.year}  ${_dos(d.hour)}:${_dos(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.pedidos,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Pedidos'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: Icon(Icons.refresh_rounded),
              onPressed: _cargando ? null : _cargar,
            ),
          ],
        ),
        body: BoundedContent(
          maxWidth: 900,
          child: _cuerpo(),
        ),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _pedidos.isEmpty) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 12),
              TextButton.icon(
                onPressed: _cargar,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _encabezado(),
          SizedBox(height: 14),
          if (_pedidos.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('No hay pedidos pendientes.',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ..._pedidos.map(_tarjeta),
        ],
      ),
    );
  }

  Widget _encabezado() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.shopping_bag_outlined,
              color: AppColors.warning, size: 18),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pedidos pendientes',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              Text(
                '${_pedidos.length} pedido(s) de clientes esperando atención.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final items = (p['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final total = double.tryParse(p['total'].toString()) ?? 0;

    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Pedido #${p['id']}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(width: 10),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Pendiente',
                      style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                Spacer(),
                Text('Bs. ${total.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ],
            ),
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 14, color: AppColors.textMuted),
                SizedBox(width: 4),
                Text((p['cliente'] ?? 'Cliente').toString(),
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5)),
                SizedBox(width: 14),
                Icon(Icons.schedule, size: 14, color: AppColors.textMuted),
                SizedBox(width: 4),
                Text(_fecha(p['fecha']?.toString()),
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
            SizedBox(height: 8),
            Divider(color: AppColors.border, height: 1),
            SizedBox(height: 8),
            for (final it in items)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${it['cantidad']} x ${it['nombre']}',
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 13)),
                    ),
                    Text(
                      'Bs. ${((double.tryParse(it['precio_unitario'].toString()) ?? 0) * (int.tryParse(it['cantidad'].toString()) ?? 0)).toStringAsFixed(2)}',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
