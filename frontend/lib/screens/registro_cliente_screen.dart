import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/boton_modo_tema.dart';
import '../navegacion.dart';
import '../widgets/pago_dialog.dart' show validarDocumento;

const _tipos = {
  'CI': 'CI',
  'NIT': 'NIT',
  'EXTRANJERO': 'Extranjero (DNI / Pasaporte)',
};

final _reEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _reTelefono = RegExp(r'^[0-9+\s\-]{6,20}$');

/// Crear cuenta de cliente (solo rol cliente). Pide los mismos datos que el
/// cajero al registrar una venta. Con la cuenta creada entra al catalogo.
class RegistroClienteScreen extends StatefulWidget {
  final String apiBase;

  const RegistroClienteScreen({super.key, required this.apiBase});

  @override
  State<RegistroClienteScreen> createState() => _RegistroClienteScreenState();
}

class _RegistroClienteScreenState extends State<RegistroClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _documentoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();

  String _tipoDocumento = 'CI';
  bool _ocultarPass = true;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl, _documentoCtrl, _emailCtrl, _telefonoCtrl,
      _direccionCtrl, _passCtrl, _pass2Ctrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    if (_enviando || !_formKey.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.apiBase}/auth/registro'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nombre': _nombreCtrl.text.trim(),
              'tipo_documento': _tipoDocumento,
              'documento': _documentoCtrl.text.trim().toUpperCase(),
              'email': _emailCtrl.text.trim(),
              'telefono': _telefonoCtrl.text.trim(),
              'direccion': _direccionCtrl.text.trim().isEmpty ? null : _direccionCtrl.text.trim(),
              'password': _passCtrl.text,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;

      if (resp.statusCode == 201) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
        Session.iniciar(
          id: data['id'] as int,
          u: data['username'] as String,
          r: data['rol'] as String,
          datosCliente: (data['cliente'] as Map?)?.cast<String, dynamic>(),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => Navegacion.inicioCliente()),
          (_) => false,
        );
        return;
      }
      String detalle = 'No se pudo crear la cuenta (${resp.statusCode}).';
      try {
        final d = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['detail'];
        if (d is String) detalle = d;
      } catch (_) {}
      setState(() => _error = detalle);
    } on TimeoutException {
      if (mounted) setState(() => _error = 'El servidor tarda en responder. Intenta de nuevo.');
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo conectar al servidor.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Crear cuenta'),
        actions: [BotonModoTema(), SizedBox(width: 8)],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Crea tu cuenta de cliente',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Para hacer pedidos desde el catalogo en linea.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                    SizedBox(height: 18),
                    _campo(
                      controller: _nombreCtrl,
                      label: 'Nombre completo *',
                      icono: Icons.person_outline,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.length < 2) return 'Ingresa tu nombre';
                        if (t.length > 100) return 'Maximo 100 caracteres';
                        return null;
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: _tipoDocumento,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceAlt,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Tipo de documento',
                        prefixIcon: Icon(Icons.assignment_ind_outlined, size: 17),
                      ),
                      items: [
                        for (final e in _tipos.entries)
                          DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) {
                        setState(() => _tipoDocumento = v!);
                        if (_documentoCtrl.text.trim().isNotEmpty) {
                          _formKey.currentState?.validate();
                        }
                      },
                    ),
                    SizedBox(height: 12),
                    _campo(
                      controller: _documentoCtrl,
                      label: '${_tipos[_tipoDocumento]} *',
                      icono: Icons.badge_outlined,
                      maxLength: 20,
                      mayusculas: true,
                      hint: switch (_tipoDocumento) {
                        'CI' => 'Ej. 1234567 o 1234567-1A',
                        'NIT' => 'Ej. 1020304050',
                        _ => 'Ej. 45678912 o AB123456',
                      },
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Campo requerido';
                        return validarDocumento(_tipoDocumento, t);
                      },
                    ),
                    _campo(
                      controller: _emailCtrl,
                      label: 'Correo electronico *',
                      icono: Icons.mail_outline,
                      helper: 'Lo usaras para iniciar sesion',
                      teclado: TextInputType.emailAddress,
                      validator: (v) => _reEmail.hasMatch((v ?? '').trim())
                          ? null
                          : 'Correo no valido',
                    ),
                    _campo(
                      controller: _telefonoCtrl,
                      label: 'Telefono *',
                      icono: Icons.phone_outlined,
                      teclado: TextInputType.phone,
                      validator: (v) => _reTelefono.hasMatch((v ?? '').trim())
                          ? null
                          : 'Telefono no valido (6 a 20 numeros)',
                    ),
                    _campo(
                      controller: _direccionCtrl,
                      label: 'Direccion (opcional)',
                      icono: Icons.home_outlined,
                      maxLength: 150,
                    ),
                    _campo(
                      controller: _passCtrl,
                      label: 'Contrasena *',
                      icono: Icons.lock_outline_rounded,
                      oculto: _ocultarPass,
                      sufijo: IconButton(
                        icon: Icon(
                            _ocultarPass
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: AppColors.textMuted),
                        onPressed: () => setState(() => _ocultarPass = !_ocultarPass),
                      ),
                      validator: (v) {
                        final t = v ?? '';
                        if (t.length < 6) return 'Minimo 6 caracteres';
                        if (t.length > 72) return 'Maximo 72 caracteres';
                        return null;
                      },
                    ),
                    _campo(
                      controller: _pass2Ctrl,
                      label: 'Confirmar contrasena *',
                      icono: Icons.lock_outline_rounded,
                      oculto: _ocultarPass,
                      validator: (v) =>
                          v != _passCtrl.text ? 'Las contrasenas no coinciden' : null,
                    ),
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: AppColors.danger, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(_error!,
                                  style: TextStyle(color: AppColors.danger, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 14),
                    ],
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _enviando ? null : _registrar,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          backgroundColor: AppColors.accent,
                        ),
                        child: _enviando
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.accentOnAccent))
                            : Text('Crear cuenta',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accentOnAccent)),
                      ),
                    ),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: _enviando ? null : () => Navigator.of(context).pop(),
                      child: Text('Ya tengo cuenta, iniciar sesion'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icono,
    String? hint,
    String? helper,
    int? maxLength,
    bool oculto = false,
    bool mayusculas = false,
    Widget? sufijo,
    TextInputType? teclado,
    FormFieldValidator<String>? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: oculto,
        maxLength: maxLength,
        keyboardType: teclado,
        textCapitalization:
            mayusculas ? TextCapitalization.characters : TextCapitalization.none,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          counterText: '',
          prefixIcon: Icon(icono, size: 17),
          suffixIcon: sufijo,
        ),
        validator: validator,
      ),
    );
  }
}
