import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';

/// Abre el dialogo para cambiar la contraseña del usuario con sesion,
/// confirmando la actual (POST /auth/cambiar-password). La sesion se mantiene.
/// Devuelve true si la contraseña se cambio.
Future<bool> mostrarCambiarPassword(BuildContext context, {required String apiBase}) async {
  final cambiada = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CambiarPasswordDialog(apiBase: apiBase),
  );
  if (cambiada == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Contraseña actualizada.'),
        backgroundColor: AppColors.accent,
      ));
  }
  return cambiada == true;
}

class CambiarPasswordDialog extends StatefulWidget {
  final String apiBase;

  const CambiarPasswordDialog({super.key, required this.apiBase});

  @override
  State<CambiarPasswordDialog> createState() => _CambiarPasswordDialogState();
}

class _CambiarPasswordDialogState extends State<CambiarPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _ocultar = true;
  bool _enviando = false;
  String? _error;
  String? _errorActual; // se muestra bajo el campo "Contraseña actual"

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_enviando) return;
    setState(() {
      _error = null;
      _errorActual = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final usuarioId = Session.usuarioId;
    if (usuarioId == null) {
      setState(() => _error = 'No hay una sesion activa. Vuelve a iniciar sesion.');
      return;
    }

    setState(() => _enviando = true);
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.apiBase}/auth/cambiar-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'usuario_id': usuarioId,
              'password_actual': _actualCtrl.text,
              'password_nueva': _nuevaCtrl.text,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.of(context).pop(true);
        return;
      }
      String detalle = 'No se pudo cambiar la contraseña (${resp.statusCode}).';
      try {
        final d = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['detail'];
        if (d is String) detalle = d;
      } catch (_) {}
      setState(() {
        if (resp.statusCode == 401) {
          _errorActual = detalle;
          _formKey.currentState!.validate();
        } else {
          _error = detalle;
        }
      });
    } on TimeoutException {
      if (mounted) setState(() => _error = 'El servidor tarda en responder. Intenta de nuevo.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Sin conexion con el servidor. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text('Cambiar contraseña'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (Session.username != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Usuario: ${Session.username}',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ),
                _campo(
                  controller: _actualCtrl,
                  label: 'Contraseña actual',
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Ingresa tu contraseña actual';
                    return _errorActual;
                  },
                  alCambiar: (_) {
                    if (_errorActual != null) setState(() => _errorActual = null);
                  },
                ),
                _campo(
                  controller: _nuevaCtrl,
                  label: 'Nueva contraseña',
                  ayuda: 'Minimo 6 caracteres',
                  validator: (v) {
                    final t = v ?? '';
                    if (t.length < 6) return 'Minimo 6 caracteres';
                    if (utf8.encode(t).length > 72) return 'Maximo 72 caracteres';
                    if (t == _actualCtrl.text) return 'Debe ser distinta de la actual';
                    return null;
                  },
                ),
                _campo(
                  controller: _confirmarCtrl,
                  label: 'Confirmar nueva contraseña',
                  validator: (v) => v != _nuevaCtrl.text ? 'Las contraseñas no coinciden' : null,
                  alEnviar: (_) => _guardar(),
                ),
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(color: AppColors.danger, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _guardar,
          child: _enviando
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accentOnAccent))
              : Text('Guardar'),
        ),
      ],
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    String? ayuda,
    FormFieldValidator<String>? validator,
    ValueChanged<String>? alCambiar,
    ValueChanged<String>? alEnviar,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: _ocultar,
        enabled: !_enviando,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          helperText: ayuda,
          prefixIcon: Icon(Icons.lock_outline_rounded, size: 17),
          suffixIcon: IconButton(
            tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
            icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 18, color: AppColors.textMuted),
            onPressed: () => setState(() => _ocultar = !_ocultar),
          ),
        ),
        validator: validator,
        onChanged: alCambiar,
        onFieldSubmitted: alEnviar,
      ),
    );
  }
}
