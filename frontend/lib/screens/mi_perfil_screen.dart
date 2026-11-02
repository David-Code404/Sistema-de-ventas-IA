import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';
import '../widgets/cambiar_password_dialog.dart';

final _reCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validarNombrePerfil(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El nombre es obligatorio';
  if (t.length > 100) return 'Máximo 100 caracteres';
  return null;
}

String? validarCorreoPerfil(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'El correo es obligatorio';
  if (t.length > 100 || !_reCorreo.hasMatch(t)) {
    return 'Correo no válido (ejemplo: nombre@correo.com)';
  }
  return null;
}

String? validarDireccionPerfil(String? valor) {
  final t = (valor ?? '').trim();
  if (t.isEmpty) return 'La dirección es obligatoria';
  if (t.length > 150) return 'Máximo 150 caracteres';
  return null;
}

/// Perfil del cliente con sesion: puede cambiar su nombre, correo, direccion y contraseña.
class MiPerfilScreen extends StatefulWidget {
  final String apiBase;

  const MiPerfilScreen({super.key, required this.apiBase});

  @override
  State<MiPerfilScreen> createState() => _MiPerfilScreenState();
}

class _MiPerfilScreenState extends State<MiPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();

  Map<String, dynamic>? _cliente;
  String _nombre0 = '';
  String _correo0 = '';
  String _direccion0 = '';
  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;

  @override
  void initState() {
    super.initState();
    for (final c in [_nombreCtrl, _correoCtrl, _direccionCtrl]) {
      c.addListener(() {
        if (_cliente != null && mounted) setState(() {});
      });
    }
    _cargar();
  }

  @override
  void dispose() {
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

  String _texto(Map<String, dynamic> c, String clave) => (c[clave] ?? '').toString().trim();

  void _cargarEnCampos(Map<String, dynamic> c) {
    _nombre0 = _texto(c, 'nombre');
    _correo0 = _texto(c, 'email');
    _direccion0 = _texto(c, 'direccion');
    _nombreCtrl.text = _nombre0;
    _correoCtrl.text = _correo0;
    _direccionCtrl.text = _direccion0;
  }

  String _detalle(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return d['detail'].toString();
    } catch (_) {
      return 'Error ${r.statusCode}';
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _errorCarga = null; });
    try {
      final r = await http.get(Uri.parse('${widget.apiBase}/mi-perfil'));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final c = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _cargarEnCampos(c);
        setState(() { _cliente = c; _cargando = false; });
      } else {
        setState(() { _cargando = false; _errorCarga = _detalle(r); });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _cargando = false; _errorCarga = 'No se pudo conectar con el servidor.'; });
    }
  }

  Future<void> _guardar() async {
    if (_cliente == null || _guardando) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    try {
      final r = await http.put(
        Uri.parse('${widget.apiBase}/mi-perfil'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre': _nombreCtrl.text.trim(),
          'email': _correoCtrl.text.trim(),
          'direccion': _direccionCtrl.text.trim(),
        }),
      );
      if (!mounted) return;
      if (r.statusCode == 200) {
        final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final c = (d['cliente'] as Map).cast<String, dynamic>();
        _cargarEnCampos(c);
        Session.cliente = c;
        Session.username = d['username'] as String?;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Mi perfil'),
      ),
      body: BoundedContent(
        maxWidth: 560,
        child: _cargando
            ? Center(child: CircularProgressIndicator())
            : _errorCarga != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorCarga!, style: TextStyle(color: AppColors.danger)),
                        SizedBox(height: 12),
                        OutlinedButton(onPressed: _cargar, child: Text('Reintentar')),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _tarjeta(_formulario(_cliente!)),
                      SizedBox(height: 16),
                      _tarjeta(_seguridad()),
                    ],
                  ),
      ),
    );
  }

  Widget _formulario(Map<String, dynamic> c) {
    final tipo = _texto(c, 'tipo_documento');
    final documento = _texto(c, 'documento');
    final telefono = _texto(c, 'telefono');
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mis datos',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
            '${tipo.isEmpty ? documento : '$tipo $documento'}'
            '${telefono.isEmpty ? '' : ' · Tel. $telefono'}',
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
            validator: validarNombrePerfil,
          ),
          SizedBox(height: 14),
          TextFormField(
            controller: _correoCtrl,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Correo electrónico',
              helperText: 'Es también el usuario con el que inicias sesión',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.mail_outline, size: 17),
            ),
            validator: validarCorreoPerfil,
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
            validator: validarDireccionPerfil,
          ),
          SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_hayCambios && !_guardando) ? _guardar : null,
            icon: _guardando
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accentOnAccent))
                : Icon(Icons.save_outlined, size: 18),
            label: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Widget _seguridad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Contraseña y seguridad',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Cambia tu contraseña o activa la verificación en dos pasos.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => mostrarCambiarPassword(context, apiBase: widget.apiBase),
          icon: Icon(Icons.lock_reset_rounded, size: 18),
          label: Text('Cambiar contraseña'),
        ),
      ],
    );
  }
}
