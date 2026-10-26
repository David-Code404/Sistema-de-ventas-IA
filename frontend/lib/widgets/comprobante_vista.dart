import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const _metodos = {'efectivo': 'Efectivo', 'tarjeta': 'Tarjeta', 'qr': 'QR'};

/// Carga los datos del comprobante de una venta finalizada
/// (GET /ventas/{id}/comprobante).
Future<Map<String, dynamic>> cargarComprobante(String apiBase, int ventaId) async {
  final resp = await http.get(Uri.parse('$apiBase/ventas/$ventaId/comprobante'));
  if (resp.statusCode != 200) {
    String detalle = 'El backend respondio ${resp.statusCode}';
    try {
      detalle = (jsonDecode(resp.body) as Map<String, dynamic>)['detail'].toString();
    } catch (_) {}
    throw Exception(detalle);
  }
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

/// Comprobante de venta con los datos guardados en el backend: numero,
/// fecha, cliente, productos, pago y total. [grande] lo dibuja a mayor
/// tamano para la vista ampliada del historial (solo si hay espacio).
class ComprobanteVista extends StatelessWidget {
  final Map<String, dynamic> datos;
  final bool grande;

  ComprobanteVista({super.key, required this.datos, this.grande = false});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _Comprobante(
        datos: datos,
        grande: grande && constraints.maxWidth >= 560,
      ),
    );
  }
}

class _Comprobante extends StatelessWidget {
  final Map<String, dynamic> datos;
  final bool grande;

  const _Comprobante({required this.datos, required this.grande});

  double _n(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
  String _bs(dynamic v) => 'Bs. ${_n(v).toStringAsFixed(2)}';
  double _t(double base) => grande ? base * 1.2 : base;

  String? _texto(String campo) {
    final v = datos[campo]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final creado = DateTime.tryParse(datos['creado_en']?.toString() ?? '');
    String dos(int n) => n.toString().padLeft(2, '0');
    final fecha = creado == null
        ? '-'
        : '${dos(creado.day)} de ${_meses[creado.month - 1]} de ${creado.year}'
            '  |  ${dos(creado.hour)}:${dos(creado.minute)}';
    final numero = datos['numero']?.toString() ?? '#${datos['id']}';
    final items = (datos['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final metodo = datos['metodo_pago']?.toString() ?? '';
    final factura = datos['factura'] == true || datos['factura'] == 1;
    final cajero = _texto('cajero');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecera(factura, cajero),
          Padding(
            padding: EdgeInsets.all(grande ? 28 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _numeroYEstado(numero, fecha),
                SizedBox(height: grande ? 22 : 16),
                _seccion('DATOS DEL CLIENTE', _datosCliente(factura)),
                SizedBox(height: grande ? 18 : 14),
                _seccion('PRODUCTOS', _tablaProductos(items)),
                SizedBox(height: grande ? 18 : 14),
                _seccion('INFORMACION DE PAGO', [
                  _fila('Metodo de pago', _metodos[metodo] ?? metodo),
                  if (metodo == 'efectivo' && datos['monto_recibido'] != null) ...[
                    _fila('Monto recibido', _bs(datos['monto_recibido'])),
                    _fila('Cambio', _bs(datos['cambio'])),
                  ] else
                    _fila('Confirmacion', 'Pago confirmado por el cajero'),
                ]),
                SizedBox(height: grande ? 18 : 14),
                _total(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabecera(bool factura, String? cajero) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, grande ? 22 : 18, 20, grande ? 20 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: Row(
        children: [
          Container(
            width: _t(42),
            height: _t(42),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text('CR',
                style: TextStyle(
                    color: AppColors.accentOnAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: _t(16))),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Caja Registradora IA',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: _t(16),
                        fontWeight: FontWeight.w700)),
                Text(
                    factura
                        ? 'Comprobante de venta  -  Factura solicitada'
                        : 'Comprobante de venta',
                    style: TextStyle(color: AppColors.accent, fontSize: _t(12))),
              ],
            ),
          ),
          if (cajero != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('ATENDIDO POR',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: _t(9),
                        letterSpacing: 0.6)),
                Text(cajero,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: _t(13),
                        fontWeight: FontWeight.w700)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _numeroYEstado(String numero, String fecha) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('COMPROBANTE',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: _t(10.5),
                      letterSpacing: 0.8)),
              Text(numero,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: _t(20),
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Venta N. ${datos['id']}  |  $fecha',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: _t(12))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, color: AppColors.accent, size: _t(15)),
              SizedBox(width: 4),
              Text('PAGADO',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: _t(12),
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _datosCliente(bool factura) {
    final nombre = _texto('cliente_nombre');
    final documento = _texto('cliente_documento');
    final email = _texto('cliente_email');
    final telefono = _texto('cliente_telefono');
    final direccion = _texto('cliente_direccion');
    final tipoDoc = switch (_texto('cliente_tipo_documento')?.toUpperCase()) {
      'CI' => 'CI',
      'NIT' => 'NIT',
      'EXTRANJERO' => 'Doc. extranjero',
      _ => 'NIT / CI',
    };
    final sinDatos = nombre == null &&
        documento == null &&
        email == null &&
        telefono == null &&
        direccion == null;
    return [
      if (sinDatos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text('Venta sin datos del cliente.',
              style: TextStyle(color: AppColors.textMuted, fontSize: _t(12.5))),
        )
      else ...[
        _fila('Nombre', nombre ?? '-'),
        _fila(tipoDoc, documento ?? '-'),
        if (email != null) _fila('Correo', email),
        if (telefono != null) _fila('Telefono', telefono),
        if (direccion != null) _fila('Direccion', direccion),
      ],
      _fila('Factura', factura ? 'Solicitada' : 'No solicitada'),
    ];
  }

  List<Widget> _tablaProductos(List<Map<String, dynamic>> items) {
    final cabecera = TextStyle(
        color: AppColors.textMuted,
        fontSize: _t(10.5),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3);
    final celda = TextStyle(color: AppColors.textPrimary, fontSize: _t(12.5));
    Widget fila(List<Widget> c) => Row(children: [
          SizedBox(width: _t(44), child: c[0]),
          Expanded(child: c[1]),
          SizedBox(width: _t(78), child: c[2]),
          SizedBox(width: _t(84), child: c[3]),
        ]);

    return [
      fila([
        Text('CANT.', style: cabecera),
        Text('PRODUCTO', style: cabecera),
        Text('P. UNIT.', style: cabecera, textAlign: TextAlign.right),
        Text('SUBTOTAL', style: cabecera, textAlign: TextAlign.right),
      ]),
      Divider(color: AppColors.border, height: 14),
      for (final it in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: fila([
            Text('${it['cantidad']}', style: celda),
            Text('${it['nombre']}', style: celda, overflow: TextOverflow.ellipsis),
            Text(_bs(it['precio_unitario']),
                style: celda.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.right),
            Text(_bs(it['subtotal']),
                style: celda.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
          ]),
        ),
    ];
  }

  Widget _seccion(String titulo, List<Widget> hijos) {
    return Container(
      padding: EdgeInsets.all(grande ? 16 : 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo,
              style: TextStyle(
                  color: AppColors.accent,
                  fontSize: _t(10.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          SizedBox(height: 8),
          ...hijos,
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: TextStyle(color: AppColors.textMuted, fontSize: _t(12.5))),
          SizedBox(width: 16),
          Expanded(
            child: Text(valor,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: _t(13),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _total() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('TOTAL',
              style: TextStyle(
                  color: AppColors.accentOnAccent,
                  fontSize: _t(12),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          SizedBox(width: 12),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(_bs(datos['total']),
                  style: TextStyle(
                      color: AppColors.accentOnAccent,
                      fontSize: _t(24),
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
