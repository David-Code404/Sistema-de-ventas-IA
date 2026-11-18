import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';

/// HU-25 - Tarea 1400: historial de compras hechas a un proveedor.
/// Solo para el Administrador. Se abre con Navigator.push desde el area
/// de proveedores, pasando el id y el nombre (razon social) del proveedor.
class HistorialComprasProveedorScreen extends StatefulWidget {
  final int proveedorId;
  final String proveedorNombre;
  final String apiBase;

  const HistorialComprasProveedorScreen({
    super.key,
    required this.proveedorId,
    required this.proveedorNombre,
    this.apiBase = AppConfig.apiBase,
  });

  @override
  State<HistorialComprasProveedorScreen> createState() =>
      _HistorialComprasProveedorScreenState();
}

/// (dias, etiqueta). 0 = todo el historial. -1 = rango personalizado.
const _rangos = [
  (0, 'Todo'),
  (30, '30 dias'),
  (90, '90 dias'),
  (365, '1 año'),
];

double _n(dynamic v) => double.tryParse('$v') ?? 0;
String _bs(dynamic v) => 'Bs. ${_n(v).toStringAsFixed(2)}';
String _dd(int x) => x.toString().padLeft(2, '0');

String _fechaHora(dynamic iso) {
  final f = DateTime.tryParse('${iso ?? ''}');
  if (f == null) return '-';
  return '${_dd(f.day)}/${_dd(f.month)}/${f.year} ${_dd(f.hour)}:${_dd(f.minute)}';
}

String _fechaCorta(DateTime d) => '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
String _fechaApi(DateTime d) => '${d.year}-${_dd(d.month)}-${_dd(d.day)}';

class _HistorialComprasProveedorScreenState
    extends State<HistorialComprasProveedorScreen> {
  int _dias = 0;
  DateTimeRange? _rangoPersonalizado;
  Map<String, dynamic>? _datos;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Session.esAdmin) _cargar();
  }

  /// Devuelve (desde, hasta) segun el filtro elegido. null = sin limite.
  (DateTime?, DateTime?) _periodo() {
    if (_dias == -1 && _rangoPersonalizado != null) {
      return (_rangoPersonalizado!.start, _rangoPersonalizado!.end);
    }
    if (_dias > 0) {
      final hoy = DateTime.now();
      final inicio = DateTime(hoy.year, hoy.month, hoy.day)
          .subtract(Duration(days: _dias - 1));
      return (inicio, null);
    }
    return (null, null);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final (desde, hasta) = _periodo();
      final params = <String, String>{
        'usuario_id': '${Session.usuarioId ?? 0}',
        if (desde != null) 'desde': _fechaApi(desde),
        if (hasta != null) 'hasta': _fechaApi(hasta),
      };
      final uri = Uri.parse(
              '${widget.apiBase}/proveedores/${widget.proveedorId}/historial-compras')
          .replace(queryParameters: params);

      final resp = await http.get(uri);
      final cuerpo = utf8.decode(resp.bodyBytes);
      if (resp.statusCode != 200) {
        String mensaje = 'El servidor respondio ${resp.statusCode}.';
        try {
          final detalle = (jsonDecode(cuerpo) as Map)['detail'];
          if (detalle is String) mensaje = detalle;
        } catch (_) {}
        throw Exception(mensaje);
      }
      if (!mounted) return;
      setState(() {
        _datos = jsonDecode(cuerpo) as Map<String, dynamic>;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _elegirRango() async {
    final hoy = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(hoy.year, hoy.month, hoy.day),
      initialDateRange: _rangoPersonalizado,
      helpText: 'Periodo de compras',
      saveText: 'Aplicar',
    );
    if (elegido == null) return;
    setState(() {
      _dias = -1;
      _rangoPersonalizado = elegido;
    });
    _cargar();
  }

  List<Map<String, dynamic>> get _compras =>
      ((_datos?['compras'] as List?) ?? []).cast<Map<String, dynamic>>();

  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Historial de compras'),
        actions: [
          if (Session.esAdmin)
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: !Session.esAdmin
          ? Center(
              child: Text('Esta seccion es solo para administradores.',
                  style: TextStyle(color: AppColors.textSecondary)))
          : _contenido(),
    );
  }

  Widget _contenido() {
    if (_cargando && _datos == null) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null && _datos == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.danger, size: 32),
              SizedBox(height: 10),
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

    final proveedor =
        ((_datos?['proveedor'] as Map?) ?? {}).cast<String, dynamic>();
    final resumen =
        ((_datos?['resumen'] as Map?) ?? {}).cast<String, dynamic>();

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: BoundedContent(
        maxWidth: 1000,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _tarjetaProveedor(proveedor),
            SizedBox(height: 16),
            _filtros(),
            if (_cargando) ...[
              SizedBox(height: 8),
              LinearProgressIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.border,
                minHeight: 2,
              ),
            ],
            if (_error != null) ...[
              SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
            ],
            SizedBox(height: 16),
            _kpis(resumen),
            SizedBox(height: 20),
            Text('COMPRAS',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7)),
            SizedBox(height: 10),
            if (_compras.isEmpty)
              _vacio()
            else
              for (final c in _compras) _compraTile(c),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Datos del proveedor ─────────────────────────────────────
  Widget _tarjetaProveedor(Map<String, dynamic> p) {
    final nombre = '${p['razon_social'] ?? widget.proveedorNombre}';
    final activo = p['activo'] != false;
    final datos = <(IconData, String)>[
      if ((p['nit'] ?? '').toString().isNotEmpty)
        (Icons.badge_outlined, 'NIT ${p['nit']}'),
      if ((p['telefono'] ?? '').toString().isNotEmpty)
        (Icons.phone_outlined, '${p['telefono']}'),
      if ((p['correo'] ?? '').toString().isNotEmpty)
        (Icons.mail_outline, '${p['correo']}'),
      if ((p['direccion'] ?? '').toString().isNotEmpty)
        (Icons.place_outlined, '${p['direccion']}'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.local_shipping_outlined,
                color: AppColors.accent, size: 21),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(nombre,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (!activo) ...[
                      SizedBox(width: 8),
                      _etiqueta('Inactivo', AppColors.danger),
                    ],
                  ],
                ),
                if (datos.isNotEmpty) ...[
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      for (final d in datos)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(d.$1, size: 14, color: AppColors.textMuted),
                            SizedBox(width: 5),
                            Text(d.$2,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12.5)),
                          ],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filtro de periodo ───────────────────────────────────────
  Widget _filtros() {
    final personalizado = _dias == -1 && _rangoPersonalizado != null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final r in _rangos)
          _chip(
            etiqueta: r.$2,
            activo: _dias == r.$1,
            onTap: () {
              if (_dias == r.$1) return;
              setState(() => _dias = r.$1);
              _cargar();
            },
          ),
        _chip(
          etiqueta: personalizado
              ? '${_fechaCorta(_rangoPersonalizado!.start)} - ${_fechaCorta(_rangoPersonalizado!.end)}'
              : 'Elegir fechas',
          icono: Icons.date_range_outlined,
          activo: personalizado,
          onTap: _elegirRango,
        ),
      ],
    );
  }

  Widget _chip({
    required String etiqueta,
    required bool activo,
    required VoidCallback onTap,
    IconData? icono,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: activo
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: activo
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[
              Icon(icono,
                  size: 14,
                  color: activo ? AppColors.accent : AppColors.textSecondary),
              SizedBox(width: 6),
            ],
            Text(etiqueta,
                style: TextStyle(
                    color: activo ? AppColors.accent : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Resumen ─────────────────────────────────────────────────
  Widget _kpis(Map<String, dynamic> r) {
    final ultima = r['ultima_compra'];
    final tarjetas = <(String, String, IconData, bool)>[
      ('TOTAL COMPRADO', _bs(r['total_comprado']), Icons.payments_outlined, true),
      ('COMPRAS', '${_n(r['compras']).toInt()}', Icons.receipt_long_outlined, false),
      ('UNIDADES', '${_n(r['unidades']).toInt()}', Icons.inventory_2_outlined, false),
      ('PROMEDIO POR COMPRA', _bs(r['promedio_por_compra']),
          Icons.calculate_outlined, false),
      ('ULTIMA COMPRA', ultima == null ? '-' : _fechaHora(ultima).split(' ').first,
          Icons.event_outlined, false),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columnas = c.maxWidth > 860 ? 5 : (c.maxWidth > 560 ? 3 : 2);
      final ancho = (c.maxWidth - (columnas - 1) * 10) / columnas;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in tarjetas)
            SizedBox(
              width: ancho,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.$4
                      ? AppColors.accent.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: t.$4
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(t.$3,
                            size: 14,
                            color: t.$4 ? AppColors.accent : AppColors.textMuted),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(t.$1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4)),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(t.$2,
                          style: TextStyle(
                              color: t.$4
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  // ── Lista de compras ────────────────────────────────────────
  Widget _vacio() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 30, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text(
            _dias == 0
                ? 'Este proveedor aun no tiene compras registradas.'
                : 'No hay compras a este proveedor en el periodo elegido.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _compraTile(Map<String, dynamic> c) {
    final items = ((c['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final productos = _n(c['productos_distintos']).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('compra_${c['id']}'),
          iconColor: AppColors.accent,
          collapsedIconColor: AppColors.textMuted,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Text('Compra #${c['id']}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              Spacer(),
              Text(_bs(c['total']),
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${_fechaHora(c['fecha'])}  ·  ${_n(c['unidades']).toInt()} uds  ·  '
              '$productos ${productos == 1 ? 'producto' : 'productos'}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          children: [
            Divider(color: AppColors.border, height: 1),
            SizedBox(height: 8),
            _filaItem('Producto', 'Cant.', 'Costo unit.', 'Subtotal',
                encabezado: true),
            for (final it in items)
              _filaItem(
                '${it['nombre']}',
                '${_n(it['cantidad']).toInt()}',
                _bs(it['costo_unitario']),
                _bs(it['subtotal']),
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Esta compra no tiene productos registrados.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filaItem(String producto, String cantidad, String costo,
      String subtotal,
      {bool encabezado = false}) {
    final estilo = encabezado
        ? TextStyle(
            color: AppColors.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4)
        : TextStyle(color: AppColors.textPrimary, fontSize: 12.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
              flex: 5,
              child: Text(encabezado ? producto.toUpperCase() : producto,
                  overflow: TextOverflow.ellipsis, style: estilo)),
          Expanded(
              flex: 2,
              child: Text(encabezado ? cantidad.toUpperCase() : cantidad,
                  textAlign: TextAlign.center, style: estilo)),
          Expanded(
              flex: 3,
              child: Text(encabezado ? costo.toUpperCase() : costo,
                  textAlign: TextAlign.right, style: estilo)),
          Expanded(
              flex: 3,
              child: Text(encabezado ? subtotal.toUpperCase() : subtotal,
                  textAlign: TextAlign.right,
                  style: encabezado
                      ? estilo
                      : estilo.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _etiqueta(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(texto,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}