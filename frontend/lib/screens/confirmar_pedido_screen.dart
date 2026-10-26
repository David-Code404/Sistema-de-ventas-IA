import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/carrito_cliente.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/boton_carrito.dart';
import '../widgets/bounded_content.dart';
import '../navegacion.dart';
import 'carrito_cliente_screen.dart';

final _reTelefono = RegExp(r'^[0-9+\s\-]{6,20}$');

/// Resumen del pedido antes de enviarlo: productos, total, datos del cliente
/// y una descripcion opcional. Crea el pedido con POST /pedidos (estado
/// 'pendiente'; el stock solo se valida, no se descuenta).
class ConfirmarPedidoScreen extends StatefulWidget {
  final String apiBase;

  const ConfirmarPedidoScreen({super.key, required this.apiBase});

  @override
  State<ConfirmarPedidoScreen> createState() => _ConfirmarPedidoScreenState();
}

class _ConfirmarPedidoScreenState extends State<ConfirmarPedidoScreen> {
  final _carrito = CarritoCliente.instance;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _telefonoCtrl;
  final _notaCtrl = TextEditingController();

  bool _enviando = false;
  String? _error;
  bool _errorSesion = false;

  @override
  void initState() {
    super.initState();
    final ficha = Session.cliente ?? {};
    _nombreCtrl = TextEditingController(text: (ficha['nombre'] ?? '').toString());
    _telefonoCtrl = TextEditingController(text: (ficha['telefono'] ?? '').toString());
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    if (_carrito.vacio) {
      setState(() => _error = 'Tu carrito esta vacio. Agrega productos desde el catalogo.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final usuarioId = Session.usuarioId;
    if (usuarioId == null || !Session.esCliente) {
      setState(() {
        _error = 'Inicia sesion para confirmar tu pedido.';
        _errorSesion = true;
      });
      return;
    }

    setState(() {
      _enviando = true;
      _error = null;
      _errorSesion = false;
    });

    try {
      final resp = await http
          .post(
            Uri.parse('${widget.apiBase}/pedidos'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'usuario_id': usuarioId,
              'items': [
                for (final i in _carrito.items)
                  {'producto_id': i.productoId, 'cantidad': i.cantidad},
              ],
              'nota': _notaCtrl.text.trim().isEmpty ? null : _notaCtrl.text.trim(),
              'cliente_nombre': _nombreCtrl.text.trim(),
              'cliente_telefono': _telefonoCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (resp.statusCode == 201) {
        final pedido = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        _carrito.vaciar();
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => PedidoConfirmadoScreen(apiBase: widget.apiBase, pedido: pedido)));
        return;
      }

      final detalle = _detalle(resp);
      if (resp.statusCode == 401) {
        setState(() {
          _error = detalle ?? 'Tu sesion no es valida. Vuelve a iniciar sesion.';
          _errorSesion = true;
        });
      } else if (resp.statusCode == 404 ||
          (resp.statusCode == 422 && (detalle ?? '').contains('stock'))) {
        // Falta stock o un producto ya no existe: actualiza el carrito
        await _resincronizar();
        if (!mounted) return;
        setState(() => _error =
            '${detalle ?? 'Un producto ya no esta disponible.'} '
            'Actualizamos tu carrito con el stock disponible; revisalo y vuelve a confirmar.');
      } else {
        setState(() => _error = detalle ?? 'Error del servidor (${resp.statusCode}). Intenta de nuevo.');
      }
    } on TimeoutException {
      if (mounted) setState(() => _error = 'El servidor tarda en responder. Revisa tu conexion e intenta de nuevo.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Sin conexion con el servidor. Revisa tu internet e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String? _detalle(http.Response r) {
    try {
      final d = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty) return 'Revisa los datos del pedido.';
    } catch (_) {}
    return null;
  }

  Future<void> _resincronizar() async {
    try {
      await sincronizarCarrito(widget.apiBase);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _carrito,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          title: Text('Confirmar pedido'),
        ),
        body: BoundedContent(
          maxWidth: 760,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _seccion('TU PEDIDO', _resumen()),
                SizedBox(height: 14),
                _seccion('TUS DATOS', _datosCliente()),
                SizedBox(height: 14),
                _seccion('DESCRIPCION (OPCIONAL)', [
                  TextFormField(
                    controller: _notaCtrl,
                    maxLength: 255,
                    minLines: 2,
                    maxLines: 4,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ej. todo en 2 bolsas, paso a recoger a las 6 pm',
                    ),
                  ),
                ]),
                if (_error != null) ...[
                  SizedBox(height: 14),
                  _mensajeError(),
                ],
                SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: (_enviando || _carrito.vacio) ? null : _confirmar,
                    icon: _enviando
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.accentOnAccent))
                        : Icon(Icons.check_circle_outline_rounded, size: 20),
                    label: Text(_enviando ? 'Enviando pedido...' : 'Confirmar pedido',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'El pedido queda pendiente hasta que el cajero lo revise.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _resumen() {
    if (_carrito.vacio) {
      return [
        Text('Tu carrito esta vacio.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ];
    }
    return [
      for (final i in _carrito.items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              ImagenProducto(apiBase: widget.apiBase, productoId: i.productoId, tamano: 40),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                    Text('${i.cantidad} x ${formatoBs(i.precio)}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Text(formatoBs(i.subtotal),
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      Divider(color: AppColors.border, height: 20),
      Row(
        children: [
          Text('TOTAL',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          Spacer(),
          Text(formatoBs(_carrito.total),
              style: TextStyle(
                  color: AppColors.accent, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    ];
  }

  List<Widget> _datosCliente() {
    return [
      TextFormField(
        controller: _nombreCtrl,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Nombre *',
          prefixIcon: Icon(Icons.person_outline, size: 17),
        ),
        validator: (v) {
          final t = (v ?? '').trim();
          if (t.length < 2) return 'Ingresa tu nombre';
          if (t.length > 100) return 'Maximo 100 caracteres';
          return null;
        },
      ),
      SizedBox(height: 10),
      TextFormField(
        controller: _telefonoCtrl,
        keyboardType: TextInputType.phone,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Telefono *',
          helperText: 'Para avisarte sobre tu pedido',
          prefixIcon: Icon(Icons.phone_outlined, size: 17),
        ),
        validator: (v) =>
            _reTelefono.hasMatch((v ?? '').trim()) ? null : 'Telefono no valido (6 a 20 numeros)',
      ),
      if (Session.username != null) ...[
        SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.mail_outline, size: 15, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text(Session.username!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ),
          ],
        ),
      ],
    ];
  }

  Widget _mensajeError() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            ],
          ),
          if (_errorSesion)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => Navegacion.login())),
                child: Text('Iniciar sesion'),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _seccion(String titulo, List<Widget> hijos) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo,
            style: TextStyle(
                color: AppColors.accent,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        SizedBox(height: 10),
        ...hijos,
      ],
    ),
  );
}

/// Confirmacion despues de crear el pedido: numero y resumen.
class PedidoConfirmadoScreen extends StatelessWidget {
  final String apiBase;
  final Map<String, dynamic> pedido;

  const PedidoConfirmadoScreen({super.key, required this.apiBase, required this.pedido});

  @override
  Widget build(BuildContext context) {
    final items = (pedido['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final total = double.tryParse('${pedido['total']}') ?? 0;
    final nota = (pedido['nota'] ?? '').toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        automaticallyImplyLeading: false,
        title: Text('Pedido enviado'),
      ),
      body: BoundedContent(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, color: AppColors.accent, size: 40),
              ),
            ),
            SizedBox(height: 14),
            Text('¡Gracias! Recibimos tu pedido',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
            SizedBox(height: 6),
            Text('Pedido N° ${pedido['pedido_id']}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.accent, fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('Estado: pendiente. El cajero revisara tu pedido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            SizedBox(height: 20),
            _seccion('RESUMEN', [
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${i['cantidad']} x ${i['nombre']}',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
                      ),
                      Text(formatoBs(double.tryParse('${i['subtotal']}') ?? 0),
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              Divider(color: AppColors.border, height: 20),
              Row(
                children: [
                  Text('TOTAL',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                  Spacer(),
                  Text(formatoBs(total),
                      style: TextStyle(
                          color: AppColors.accent, fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
            ]),
            SizedBox(height: 14),
            _seccion('DATOS DEL PEDIDO', [
              _fila('Nombre', '${pedido['cliente_nombre'] ?? '-'}'),
              _fila('Telefono', '${pedido['cliente_telefono'] ?? '-'}'),
              if (nota.isNotEmpty) _fila('Descripcion', nota),
            ]),
            SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: Icon(Icons.storefront_outlined, size: 18),
              label: Text('Volver al catalogo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(etiqueta,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ),
            Expanded(
              child: Text(valor,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
