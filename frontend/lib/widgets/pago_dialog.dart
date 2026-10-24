import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/cart_item.dart';
import '../theme/app_colors.dart';

class ResultadoPago {
  final String metodo;
  final double? montoRecibido;
  final bool confirmado;
  final bool factura;
  final String? clienteNombre;
  final String? clienteDocumento;
  final String? clienteTipoDocumento;
  final String? clienteEmail;
  final String? clienteDireccion;
  final String? clienteTelefono;

  ResultadoPago({
    required this.metodo,
    required this.montoRecibido,
    required this.confirmado,
    this.factura = false,
    this.clienteNombre,
    this.clienteDocumento,
    this.clienteTipoDocumento,
    this.clienteEmail,
    this.clienteDireccion,
    this.clienteTelefono,
  });
}

Future<ResultadoPago?> mostrarDialogoPago(
  BuildContext context, {
  required List<CartItem> items,
  required double total,
}) {
  return showDialog<ResultadoPago>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PagoDialog(items: items, total: total),
  );
}

// Formatos de documento del cliente (iguales a FORMATOS_DOCUMENTO en backend/db.py)
const _tiposDocumento = {
  'CI': 'CI',
  'NIT': 'NIT',
  'EXTRANJERO': 'Extranjero (DNI / Pasaporte)',
};

String? validarDocumento(String tipo, String valor) {
  final t = valor.trim().toUpperCase();
  switch (tipo) {
    case 'CI':
      if (!RegExp(r'^\d{5,10}(-\d[A-Z])?$').hasMatch(t)) {
        return '5 a 10 digitos (complemento opcional: 1234567-1A)';
      }
    case 'NIT':
      if (!RegExp(r'^\d{7,13}$').hasMatch(t)) return 'Solo numeros (7 a 13 digitos)';
    case 'EXTRANJERO':
      if (!RegExp(r'^(?=.*\d)[A-Z0-9][A-Z0-9\-]{4,18}[A-Z0-9]$').hasMatch(t)) {
        return '6 a 20 letras o numeros, con al menos un numero';
      }
  }
  return null;
}

class _PagoDialog extends StatefulWidget {
  final List<CartItem> items;
  final double total;

  const _PagoDialog({required this.items, required this.total});

  @override
  State<_PagoDialog> createState() => _PagoDialogState();
}

class _PagoDialogState extends State<_PagoDialog> {
  final _montoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _clienteFormKey = GlobalKey<FormState>();

  // 0 = confirmar lista, 1 = datos del cliente, 2 = pago
  int _paso = 0;
  bool _factura = false;
  String _tipoDocumento = 'CI';
  String? _metodo;
  bool _pagoAprobado = false;

  // Búsqueda del cliente por su documento (CI)
  bool _buscando = false;
  String? _msgBusqueda;
  bool _busquedaOk = false;
  Timer? _debounce;
  Map<String, String>? _cargado; // datos tal como estaban en la base

  bool get _datosEditados {
    final c = _cargado;
    if (c == null) return false;
    return _nombreCtrl.text.trim() != c['nombre'] ||
        _emailCtrl.text.trim() != c['email'] ||
        _direccionCtrl.text.trim() != c['direccion'] ||
        _telefonoCtrl.text.trim() != c['telefono'];
  }

  // Autocompleta sola cuando el documento ya tiene un formato válido.
  void _alCambiarDocumento(String v) {
    _debounce?.cancel();
    _cargado = null;
    final t = v.trim().toUpperCase();
    setState(() => _msgBusqueda = null);
    if (t.isEmpty || validarDocumento(_tipoDocumento, t) != null) return;
    _debounce = Timer(const Duration(milliseconds: 600), _buscarCliente);
  }

  Future<void> _buscarCliente() async {
    final doc = _documentoCtrl.text.trim().toUpperCase();
    if (doc.isEmpty) {
      setState(() {
        _busquedaOk = false;
        _msgBusqueda = 'Escribe el documento del cliente para buscarlo.';
      });
      return;
    }
    final error = validarDocumento(_tipoDocumento, doc);
    if (error != null) {
      setState(() {
        _busquedaOk = false;
        _msgBusqueda = error;
      });
      return;
    }
    setState(() {
      _buscando = true;
      _msgBusqueda = null;
    });
    try {
      final r = await http.get(Uri.parse(
          '${AppConfig.apiBase}/clientes/${Uri.encodeComponent(doc)}'));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final c = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _nombreCtrl.text = (c['nombre'] ?? '').toString();
          _emailCtrl.text = (c['email'] ?? '').toString();
          _direccionCtrl.text = (c['direccion'] ?? '').toString();
          _telefonoCtrl.text = (c['telefono'] ?? '').toString();
          final tipo = (c['tipo_documento'] ?? '').toString();
          if (_tiposDocumento.containsKey(tipo)) _tipoDocumento = tipo;
          _cargado = {
            'nombre': _nombreCtrl.text.trim(),
            'email': _emailCtrl.text.trim(),
            'direccion': _direccionCtrl.text.trim(),
            'telefono': _telefonoCtrl.text.trim(),
          };
          _busquedaOk = true;
          _msgBusqueda = 'Cliente encontrado: datos cargados.';
        });
      } else if (r.statusCode == 404) {
        setState(() {
          _busquedaOk = false;
          _msgBusqueda = 'Cliente no encontrado. Llena sus datos para registrarlo.';
        });
      } else {
        setState(() {
          _busquedaOk = false;
          _msgBusqueda = 'No se pudo buscar (error ${r.statusCode}).';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busquedaOk = false;
        _msgBusqueda = 'No se pudo conectar con el servidor.';
      });
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_nombreCtrl, _emailCtrl, _direccionCtrl, _telefonoCtrl]) {
      c.addListener(() {
        if (_cargado != null && mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _montoCtrl.dispose();
    _nombreCtrl.dispose();
    _documentoCtrl.dispose();
    _emailCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  double? get _monto => double.tryParse(_montoCtrl.text.trim().replaceAll(',', '.'));

  bool get _puedeCobrar {
    switch (_metodo) {
      case 'efectivo':
        final m = _monto;
        return m != null && m >= widget.total;
      case 'tarjeta':
      case 'qr':
        return _pagoAprobado;
      default:
        return false;
    }
  }

  String? _valor(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _cobrar() {
    Navigator.pop(
      context,
      ResultadoPago(
        metodo: _metodo!,
        montoRecibido: _metodo == 'efectivo' ? _monto : null,
        confirmado: _pagoAprobado,
        factura: _factura,
        clienteNombre: _valor(_nombreCtrl),
        clienteDocumento: _valor(_documentoCtrl)?.toUpperCase(),
        clienteTipoDocumento: _valor(_documentoCtrl) == null ? null : _tipoDocumento,
        clienteEmail: _valor(_emailCtrl),
        clienteDireccion: _valor(_direccionCtrl),
        clienteTelefono: _valor(_telefonoCtrl),
      ),
    );
  }

  void _continuarDeCliente() {
    if (_clienteFormKey.currentState!.validate()) {
      setState(() => _paso = 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = switch (_paso) {
      0 => 'Confirmar lista de productos',
      1 => 'Datos del cliente',
      _ => 'Cobrar venta',
    };
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text(
        titulo,
        style: TextStyle(
            color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: switch (_paso) {
            0 => _buildLista(),
            1 => _buildCliente(),
            _ => _buildPago(),
          },
        ),
      ),
      actions: switch (_paso) {
        0 => _accionesLista(),
        1 => _accionesCliente(),
        _ => _accionesPago(),
      },
    );
  }

  // ── Paso 1: confirmar la lista ──────────────────────────────
  Widget _buildLista() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Revisa los productos antes de cobrar.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        SizedBox(height: 12),
        for (final it in widget.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('${it.quantity} x ${it.name}',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                ),
                Text('S/ ${it.subtotal.toStringAsFixed(2)}',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        Divider(color: AppColors.border, height: 24),
        _filaTotal(),
      ],
    );
  }

  List<Widget> _accionesLista() => [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => setState(() => _paso = 1),
          child: Text('Confirmar lista'),
        ),
      ];

  // ── Paso 2: datos del cliente y factura ─────────────────────
  Widget _buildCliente() {
    return Form(
      key: _clienteFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _factura
                  ? AppColors.accent.withValues(alpha: 0.10)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _factura
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : AppColors.border),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _factura,
              onChanged: (v) {
                setState(() => _factura = v);
                _clienteFormKey.currentState?.validate();
              },
              title: Text('El cliente quiere factura',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                _factura
                    ? 'Nombre y documento (CI, NIT o extranjero) son obligatorios.'
                    : 'Sin factura: los datos del cliente son opcionales.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          ),
          SizedBox(height: 14),
          TextFormField(
            controller: _nombreCtrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: _factura ? 'Nombre del cliente *' : 'Nombre del cliente',
              prefixIcon: Icon(Icons.person_outline, size: 17),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (_factura && t.isEmpty) return 'Obligatorio para la factura';
              if (t.length > 100) return 'Maximo 100 caracteres';
              return null;
            },
          ),
          SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _tipoDocumento,
            dropdownColor: AppColors.surfaceAlt,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Tipo de documento',
              prefixIcon: Icon(Icons.assignment_ind_outlined, size: 17),
            ),
            items: [
              for (final e in _tiposDocumento.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) {
              setState(() => _tipoDocumento = v!);
              if (_documentoCtrl.text.trim().isNotEmpty) {
                _clienteFormKey.currentState?.validate();
              }
            },
          ),
          SizedBox(height: 10),
          TextFormField(
            controller: _documentoCtrl,
            maxLength: 20,
            keyboardType: _tipoDocumento == 'NIT'
                ? TextInputType.number
                : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: _factura
                  ? '${_tiposDocumento[_tipoDocumento]} *'
                  : _tiposDocumento[_tipoDocumento],
              hintText: switch (_tipoDocumento) {
                'CI' => 'Ej. 1234567 o 1234567-1A',
                'NIT' => 'Ej. 1020304050',
                _ => 'Ej. 45678912 o AB123456',
              },
              counterText: '',
              prefixIcon: Icon(Icons.badge_outlined, size: 17),
              suffixIcon: _buscando
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Buscar cliente por documento',
                      icon: Icon(Icons.search_rounded, size: 19),
                      onPressed: _buscarCliente,
                    ),
            ),
            onFieldSubmitted: (_) => _buscarCliente(),
            onChanged: _alCambiarDocumento,
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return _factura ? 'Obligatorio para la factura' : null;
              return validarDocumento(_tipoDocumento, t);
            },
          ),
          if (_msgBusqueda != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_msgBusqueda!,
                  style: TextStyle(
                      color: _busquedaOk ? AppColors.accent : AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          if (_cargado != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _datosEditados
                    ? 'Datos modificados: se actualizarán en la factura y en el cliente al cobrar.'
                    : 'Puedes editar cualquiera de los datos antes de facturar.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          SizedBox(height: 10),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Correo (opcional)',
              prefixIcon: Icon(Icons.mail_outline, size: 17),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                return 'Correo no valido';
              }
              return null;
            },
          ),
          SizedBox(height: 10),
          TextFormField(
            controller: _direccionCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Dirección (opcional)',
              prefixIcon: Icon(Icons.home_outlined, size: 17),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.length > 150) return 'Máximo 150 caracteres';
              return null;
            },
          ),
          SizedBox(height: 10),
          TextFormField(
            controller: _telefonoCtrl,
            keyboardType: TextInputType.phone,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Telefono (opcional)',
              prefixIcon: Icon(Icons.phone_outlined, size: 17),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isNotEmpty && !RegExp(r'^[0-9+\s\-]{6,20}$').hasMatch(t)) {
                return 'Telefono no valido';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _accionesCliente() => [
        TextButton(
          onPressed: () => setState(() => _paso = 0),
          child: Text('Volver a la lista'),
        ),
        FilledButton(
          onPressed: _continuarDeCliente,
          child: Text('Continuar al pago'),
        ),
      ];

  // ── Paso 3: pago ────────────────────────────────────────────
  Widget _buildPago() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filaTotal(),
        SizedBox(height: 16),
        Text('Metodo de pago',
            style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Row(
          children: [
            _opcionMetodo('efectivo', 'Efectivo', Icons.payments_outlined),
            SizedBox(width: 8),
            _opcionMetodo('tarjeta', 'Tarjeta', Icons.credit_card_outlined),
            SizedBox(width: 8),
            _opcionMetodo('qr', 'QR', Icons.qr_code_2_rounded),
          ],
        ),
        SizedBox(height: 16),
        if (_metodo == 'efectivo') _detalleEfectivo(),
        if (_metodo == 'tarjeta')
          _detalleConfirmacion(
            ayuda: 'Cobra con el POS externo y confirma si el pago fue aprobado.',
            etiquetaBoton: 'Confirmar que el pago fue aprobado',
            visual: _visualTarjeta(),
          ),
        if (_metodo == 'qr')
          _detalleConfirmacion(
            ayuda: 'El cliente escanea el QR y paga desde su app del banco.',
            etiquetaBoton: 'Confirmar que llego el pago',
            visual: _visualQr(),
          ),
      ],
    );
  }

  Widget _filaTotal() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('TOTAL',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        Text('S/ ${widget.total.toStringAsFixed(2)}',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _opcionMetodo(String valor, String etiqueta, IconData icono) {
    final activo = _metodo == valor;
    final color = activo ? AppColors.accent : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() {
          _metodo = valor;
          _pagoAprobado = false;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: activo
                ? AppColors.accent.withValues(alpha: 0.12)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: activo
                    ? AppColors.accent.withValues(alpha: 0.6)
                    : AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icono, color: color, size: 22),
              SizedBox(height: 6),
              Text(etiqueta,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detalleEfectivo() {
    final m = _monto;
    Widget? resultado;
    if (m != null) {
      final diferencia = m - widget.total;
      resultado = diferencia >= 0
          ? Text('Cambio a devolver: S/ ${diferencia.toStringAsFixed(2)}',
              style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700))
          : Text('Falta: S/ ${(-diferencia).toStringAsFixed(2)}',
              style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _montoCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Monto recibido (S/)',
            prefixIcon: Icon(Icons.payments_outlined, size: 17),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (resultado != null) ...[
          SizedBox(height: 10),
          resultado,
        ],
      ],
    );
  }

  Widget _visualQr() {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset('assets/qr_pago.jpg', width: 230, fit: BoxFit.contain),
      ),
    );
  }

  Widget _visualTarjeta() {
    return Center(
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3A5F), Color(0xFF0F766E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.contactless_outlined, color: Colors.white70, size: 28),
            SizedBox(height: 22),
            Text('4242 4242 4242 4242',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 10),
            Text('Pago con tarjeta en el POS',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _detalleConfirmacion({
    required String ayuda,
    required String etiquetaBoton,
    required Widget visual,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ayuda,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        SizedBox(height: 12),
        visual,
        SizedBox(height: 14),
        _pagoAprobado
            ? FilledButton.icon(
                onPressed: () => setState(() => _pagoAprobado = false),
                icon: Icon(Icons.check_circle_rounded, size: 18),
                label: Text('Pago confirmado'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentOnAccent),
              )
            : OutlinedButton.icon(
                onPressed: () => setState(() => _pagoAprobado = true),
                icon: Icon(Icons.task_alt_rounded, size: 18),
                label: Text(etiquetaBoton),
              ),
      ],
    );
  }

  List<Widget> _accionesPago() => [
        TextButton(
          onPressed: () => setState(() => _paso = 1),
          child: Text('Volver'),
        ),
        FilledButton.icon(
          onPressed: _puedeCobrar ? _cobrar : null,
          icon: Icon(Icons.check_circle_outline, size: 17),
          label: Text('Cobrar y cerrar venta'),
        ),
      ];
}