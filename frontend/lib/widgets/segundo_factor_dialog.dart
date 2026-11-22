import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';

final _reCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Verificacion en dos pasos (HU-24): el cliente la activa o desactiva desde su cuenta; para administrador y
/// cajero es obligatoria y solo pueden cambiar el correo donde reciben el codigo.
Future<void> mostrarSegundoFactor(BuildContext context, {required String apiBase}) async {
  final cambio = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SegundoFactorDialog(apiBase: apiBase),
  );
  if (cambio != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(cambio), backgroundColor: AppColors.accent));
  }
}

class SegundoFactorDialog extends StatefulWidget {
  final String apiBase;

  const SegundoFactorDialog({super.key, required this.apiBase});

  @override
  State<SegundoFactorDialog> createState() => _SegundoFactorDialogState();
}

class _SegundoFactorDialogState extends State<SegundoFactorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _correoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  Map<String, dynamic>? _estado;
  bool _activo = false;
  bool _cargando = true;
  bool _enviando = false;
  bool _ocultar = true;
  String? _error;

  bool get _obligatorio => _estado?['obligatorio'] == true;
  bool get _disponible => _estado?['disponible'] == true;
  String? get _correoActual => _estado?['correo'] as String?;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _detalle(http.Response r, String porDefecto) {
    try {
      final d = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['detail'];
      if (d is String) return d;
    } catch (_) {}
    return porDefecto;
  }

  Future<void> _cargar() async {
    final id = Session.usuarioId;
    if (id == null) {
      setState(() { _cargando = false; _error = 'No hay una sesion activa. Vuelve a iniciar sesion.'; });
      return;
    }
    try {
      final r = await http
          .get(Uri.parse('${widget.apiBase}/auth/2fa/estado?usuario_id=$id'))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final e = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        setState(() { _estado = e; _activo = e['activo'] == true; _cargando = false; });
      } else {
        setState(() { _cargando = false; _error = _detalle(r, 'No se pudo cargar (${r.statusCode}).'); });
      }
    } catch (_) {
      if (mounted) setState(() { _cargando = false; _error = 'Sin conexion con el servidor.'; });
    }
  }

  Future<void> _guardar() async {
    if (_enviando || _estado == null) return;
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final correoNuevo = _correoCtrl.text.trim();
    final cambioActivo = !_obligatorio && _activo != (_estado!['activo'] == true);
    if (!cambioActivo && correoNuevo.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _enviando = true);
    try {
      final r = await http
          .put(
            Uri.parse('${widget.apiBase}/auth/2fa/configuracion'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'usuario_id': Session.usuarioId,
              'password': _passCtrl.text,
              if (!_obligatorio) 'activo': _activo,
              if (correoNuevo.isNotEmpty) 'correo': correoNuevo,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final e = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        Navigator.of(context).pop(_obligatorio
            ? 'Correo de verificacion actualizado.'
            : (e['activo'] == true ? 'Verificacion en dos pasos activada.' : 'Verificacion en dos pasos desactivada.'));
        return;
      }
      setState(() => _error = _detalle(r, 'No se pudo guardar (${r.statusCode}).'));
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
      title: Text('Verificacion en dos pasos'),
      content: SizedBox(
        width: 420,
        child: _cargando
            ? SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(child: _contenido()),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: Text('Cerrar'),
        ),
        if (_estado != null && _disponible)
          FilledButton(
            onPressed: _enviando ? null : _guardar,
            child: _enviando
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentOnAccent))
                : Text('Guardar'),
          ),
      ],
    );
  }

  Widget _contenido() {
    if (_estado == null) return _caja(_error ?? 'No se pudo cargar.', error: true);
    if (!_disponible) {
      return _caja('El envio de correos todavia no esta configurado en el servidor, por eso la verificacion '
          'en dos pasos no esta disponible. Avisa al administrador del sistema.');
    }
    final tieneCorreo = _estado!['tiene_correo'] == true;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Al iniciar sesion te enviamos un codigo de 6 digitos a tu correo. Vale 5 minutos y se usa una sola vez.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          SizedBox(height: 12),
          if (_obligatorio)
            _caja('Es obligatoria para tu rol (${Session.esAdmin ? 'administrador' : 'cajero'}).')
          else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Activar verificacion en dos pasos'),
              value: _activo,
              onChanged: _enviando ? null : (v) => setState(() => _activo = v),
            ),
          SizedBox(height: 8),
          if (tieneCorreo)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Correo actual: $_correoActual',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          TextFormField(
            controller: _correoCtrl,
            enabled: !_enviando,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: tieneCorreo ? 'Cambiar correo (opcional)' : 'Correo para recibir el codigo',
              prefixIcon: Icon(Icons.mail_outline, size: 17),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return (!tieneCorreo && (_obligatorio || _activo)) ? 'Escribe tu correo' : null;
              if (t.length > 100 || !_reCorreo.hasMatch(t)) return 'Correo no valido (ejemplo: nombre@correo.com)';
              return null;
            },
          ),
          SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            obscureText: _ocultar,
            enabled: !_enviando,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Tu contraseña (para confirmar)',
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 17),
              suffixIcon: IconButton(
                tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18, color: AppColors.textMuted),
                onPressed: () => setState(() => _ocultar = !_ocultar),
              ),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Ingresa tu contraseña' : null,
            onFieldSubmitted: (_) => _guardar(),
          ),
          if (_error != null) ...[
            SizedBox(height: 12),
            _caja(_error!, error: true),
          ],
        ],
      ),
    );
  }

  Widget _caja(String texto, {bool error = false}) {
    final color = error ? AppColors.danger : AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(texto, style: TextStyle(color: color, fontSize: 13))),
        ],
      ),
    );
  }
}
