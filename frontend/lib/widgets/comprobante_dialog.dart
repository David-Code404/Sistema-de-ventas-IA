import 'package:flutter/material.dart';

import '../models/cart_item.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import 'descarga.dart';

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

Future<void> mostrarComprobante(
  BuildContext context, {
  required String apiBase,
  required int ventaId,
  required List<CartItem> items,
  required double total,
  required String metodo,
  double? montoRecibido,
  double? cambio,
  bool factura = false,
  String? clienteNombre,
  String? clienteDocumento,
  String? clienteEmail,
  String? clienteTelefono,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ComprobanteDialog(
      apiBase: apiBase,
      ventaId: ventaId,
      items: items,
      total: total,
      metodo: metodo,
      montoRecibido: montoRecibido,
      cambio: cambio,
      factura: factura,
      clienteNombre: clienteNombre,
      clienteDocumento: clienteDocumento,
      clienteEmail: clienteEmail,
      clienteTelefono: clienteTelefono,
    ),
  );
}

class _ComprobanteDialog extends StatelessWidget {
  final String apiBase;
  final int ventaId;
  final List<CartItem> items;
  final double total;
  final String metodo;
  final double? montoRecibido;
  final double? cambio;
  final bool factura;
  final String? clienteNombre;
  final String? clienteDocumento;
  final String? clienteEmail;
  final String? clienteTelefono;

  const _ComprobanteDialog({
    required this.apiBase,
    required this.ventaId,
    required this.items,
    required this.total,
    required this.metodo,
    required this.montoRecibido,
    required this.cambio,
    required this.factura,
    required this.clienteNombre,
    required this.clienteDocumento,
    required this.clienteEmail,
    required this.clienteTelefono,
  });

  String get _metodoTexto {
    switch (metodo) {
      case 'efectivo':
        return 'Efectivo';
      case 'tarjeta':
        return 'Tarjeta';
      case 'qr':
        return 'QR';
      default:
        return metodo;
    }
  }

  String _bs(double v) => 'Bs. ${v.toStringAsFixed(2)}';

  void _descargar() {
    final atendido = Uri.encodeQueryComponent(Session.username ?? '');
    descargarDesde('$apiBase/ventas/$ventaId/comprobante.pdf?atendido_por=$atendido');
  }

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final numero = 'CR-${ahora.year}-${ventaId.toString().padLeft(8, '0')}';
    final fecha = '${ahora.day.toString().padLeft(2, '0')} de ${_meses[ahora.month - 1]} de ${ahora.year}';
    final hora =
        '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';

    return Dialog(
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                    bottom: BorderSide(color: AppColors.accent, width: 3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text('CR',
                        style: TextStyle(
                            color: AppColors.accentOnAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Caja Registradora IA',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        Text('Comprobante de venta',
                            style: TextStyle(
                                color: AppColors.accent, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('COMPROBANTE',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 10.5,
                                      letterSpacing: 0.8)),
                              Text(numero,
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              SizedBox(height: 4),
                              Text('$fecha  |  $hora',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded,
                                  color: AppColors.accent, size: 15),
                              SizedBox(width: 4),
                              Text('PAGADO',
                                  style: TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                border: i == 0
                                    ? null
                                    : Border(
                                        top: BorderSide(
                                            color: AppColors.border)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        '${items[i].quantity} x ${items[i].name}',
                                        style: TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13)),
                                  ),
                                  Text(_bs(items[i].subtotal),
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14),
                    if (clienteNombre != null || clienteDocumento != null) ...[
                      _fila('Cliente', clienteNombre ?? '-'),
                      _fila('NIT / CI', clienteDocumento ?? '-'),
                      if (clienteEmail != null) _fila('Correo', clienteEmail!),
                      if (clienteTelefono != null) _fila('Telefono', clienteTelefono!),
                    ],
                    _fila('Factura', factura ? 'Solicitada' : 'No solicitada'),
                    _fila('Metodo de pago', _metodoTexto),
                    if (metodo == 'efectivo' && montoRecibido != null) ...[
                      _fila('Monto recibido', _bs(montoRecibido!)),
                      _fila('Cambio', _bs(cambio ?? 0)),
                    ],
                    SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8)),
                          Text(_bs(total),
                              style: TextStyle(
                                  color: AppColors.accentOnAccent,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cerrar'),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _descargar,
                      icon: Icon(Icons.download_rounded, size: 18),
                      label: Text('Descargar PDF'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          Text(valor,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
