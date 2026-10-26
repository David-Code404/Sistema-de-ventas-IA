import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';
import '../widgets/pago_dialog.dart' show validarDocumento;

// ── Validaciones (campos vacíos y formato de correo) ─────────
final _reCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validarNombre(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El nombre es obligatorio';
  if (t.length > 100) return 'Máximo 100 caracteres';
  return null;
}

String? validarCorreo(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El correo es obligatorio';
  if (t.length > 100 || !_reCorreo.hasMatch(t)) {
    return 'Correo no válido (ejemplo: nombre@correo.com)';
  }
  return null;
}

String? validarDireccion(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'La dirección es obligatoria';
  // 150 = mismo límite que el formulario de la venta y el backend.
  if (t.length > 150) return 'Máximo 150 caracteres';
  return null;
}

const _tiposDocumento = ['CI', 'NIT', 'EXTRANJERO'];

/// Valida el documento de búsqueda: debe ser un CI, NIT o documento
/// extranjero con formato válido.
String? validarDocumentoBusqueda(String? valor) {
  final t = (valor ?? '').trim().toUpperCase();
  if (t.isEmpty) return 'Escribe el documento del cliente';
  if (_tiposDocumento.any((tipo) => validarDocumento(tipo, t) == null)) {
    return null;
  }
  return 'Documento no válido (CI, NIT o extranjero)';
}

/// Perfil del cliente: se busca por su documento (automático o con la lupa)
/// y se pueden editar su nombre, correo y dirección.
class PerfilClienteScreen extends StatefulWidget {
  final String apiBase;

  const PerfilClienteScreen({super.key, required this.apiBase});

  @override
  State<PerfilClienteScreen> createState() => _PerfilClienteScreenState();
}

class _PerfilClienteScreenState extends State<PerfilClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _documentoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  Timer? _debounce;
  int _seq = 0; // descarta respuestas de búsquedas viejas
  bool _buscando = false;
  bool _guardando = false;
  String? _mensaje;
  bool _mensajeOk = false;

  Map<String, dynamic>? _cliente; // cliente cargado desde la base
  String _nombre0 = '';
  String _correo0 = '';
  String _direccion0 = '';

  @override
  void initState() {
    super.initState();
    for (final c in [_nombreCtrl, _correoCtrl, _direccionCtrl]) {
      c.addListener(() {
        if (_cliente != null && mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _documentoCtrl.dispose();
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  bool get _hayCambios =>
      _cliente != null &&
      (_nombreCtrl.text.trim() != _nombre0 ||
          _correoCtrl.text.trim() != _correo0 ||
          _direccionCtrl.text.trim() != _direccion0);

  String _texto(Map<String, dynamic> c, String clave) =>
      (c[clave] ?? '').toString().trim();

  void _cargarEnCampos(Map<String, dynamic> c) {
    _nombre0 = _texto(c, 'nombre');
    _correo0 = _texto(c, 'email');
    _direccion0 = _texto(c, 'direccion');
    _nombreCtrl.text = _nombre0;
    _correoCtrl.text = _correo0;
    _direccionCtrl.text = _direccion0;
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  String _detalle(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return d['detail'].toString();
    } catch (_) {
      return 'Error ${r.statusCode}';
    }
  }

  // ── Búsqueda por documento ──────────────────────────────────
  void _alCambiarDocumento(String v) {
    _debounce?.cancel();
    if (_cliente != null || _mensaje != null) {
      setState(() {
        _cliente = null;
        _mensaje = null;
      });
    }
    // Busca sola cuando el documento ya tiene un formato válido.
    if (validarDocumentoBusqueda(v) == null) {
      _debounce = Timer(const Duration(milliseconds: 600), _buscar);
    }
  }

  Future<void> _buscar() async {
    _debounce?.cancel();
    final doc = _documentoCtrl.text.trim().toUpperCase();
    final error = validarDocumentoBusqueda(doc);
    if (error != null) {
      setState(() {
        _cliente = null;
        _mensajeOk = false;
        _mensaje = error;
      });
      return;
    }

    final seq = ++_seq;
    setState(() {
      _buscando = true;
      _mensaje = null;
    });
    try {
      final r = await http.get(Uri.parse(
          '${widget.apiBase}/clientes/${Uri.encodeComponent(doc)}'));
      if (!mounted) return;
      // Si el cajero cambió el documento mientras se buscaba, se descarta.
      if (seq != _seq || _documentoCtrl.text.trim().toUpperCase() != doc) return;

      if (r.statusCode == 200) {
        final c = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _cargarEnCampos(c);
        setState(() {
          _cliente = c;
          _mensajeOk = true;
          _mensaje = 'Cliente encontrado.';
        });
      } else if (r.statusCode == 404) {
        setState(() {
          _cliente = null;
          _mensajeOk = false;
          _mensaje =
              'Cliente no encontrado. Se registra al cobrar una venta con sus datos.';
        });
      } else {
        setState(() {
          _cliente = null;
          _mensajeOk = false;
          _mensaje = 'No se pudo buscar (error ${r.statusCode}).';
        });
      }
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _cliente = null;
        _mensajeOk = false;
        _mensaje = 'No se pudo conectar con el servidor.';
      });
    } finally {
      if (mounted && seq == _seq) setState(() => _buscando = false);
    }
  }

  // ── Guardar cambios ─────────────────────────────────────────
  Future<void> _guardar() async {
    final actual = _cliente;
    if (actual == null || _guardando) return;
    if (!_formKey.currentState!.validate()) return;

    final documento = _texto(actual, 'documento');
    setState(() => _guardando = true);
    try {
      final r = await http.put(
        Uri.parse('${widget.apiBase}/clientes/${Uri.encodeComponent(documento)}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre': _nombreCtrl.text.trim(),
          'email': _correoCtrl.text.trim(),
          'direccion': _direccionCtrl.text.trim(),
        }),
      );
      if (!mounted) return;
      if (r.statusCode == 200) {
        final c = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _cargarEnCampos(c);
        setState(() => _cliente = c);
        _aviso('Perfil actualizado.');
      } else {
        _aviso(_detalle(r), error: true);
      }
    } catch (_) {
      _aviso('No se pudo conectar con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Perfil del cliente'),
      ),
      body: BoundedContent(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _tarjeta(_buildBusqueda()),
            if (_cliente != null) ...[
              SizedBox(height: 16),
              _tarjeta(_buildPerfil(_cliente!)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(Widget hijo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: hijo,
    );
  }

  Widget _buildBusqueda() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Buscar cliente',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Escribe su CI, NIT o documento: se busca solo o con la lupa.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        SizedBox(height: 14),
        TextField(
          controller: _documentoCtrl,
          maxLength: 20,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Documento (CI, NIT o extranjero)',
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
                    tooltip: 'Buscar cliente',
                    icon: Icon(Icons.search_rounded, size: 19),
                    onPressed: _buscar,
                  ),
          ),
          onChanged: _alCambiarDocumento,
          onSubmitted: (_) => _buscar(),
        ),
        if (_mensaje != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_mensaje!,
                style: TextStyle(
                    color: _mensajeOk ? AppColors.accent : AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _buildPerfil(Map<String, dynamic> c) {
    final tipo = _texto(c, 'tipo_documento');
    final documento = _texto(c, 'documento');
    final compras = (c['total_compras'] as num?)?.toInt();

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tipo.isEmpty ? documento : '$tipo $documento',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
            compras == null
                ? 'Todos los campos son obligatorios.'
                : 'Todos los campos son obligatorios · $compras '
                    '${compras == 1 ? 'compra registrada' : 'compras registradas'}',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          SizedBox(height: 16),
          TextFormField(
            controller: _nombreCtrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Nombre',
              prefixIcon: Icon(Icons.person_outline, size: 17),
            ),
            validator: validarNombre,
          ),
          SizedBox(height: 14),
          TextFormField(
            controller: _correoCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Correo electrónico',
              prefixIcon: Icon(Icons.mail_outline, size: 17),
            ),
            validator: validarCorreo,
          ),
          SizedBox(height: 14),
          TextFormField(
            controller: _direccionCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _hayCambios ? _guardar() : null,
            decoration: InputDecoration(
              labelText: 'Dirección',
              prefixIcon: Icon(Icons.location_on_outlined, size: 17),
            ),
            validator: validarDireccion,
          ),
          SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_hayCambios && !_guardando) ? _guardar : null,
            icon: _guardando
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.save_outlined, size: 18),
            label: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }
}