import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_colors.dart';

String _detalle(http.Response r, String porDefecto) {
  try {
    final d = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['detail'];
    if (d is String && d.isNotEmpty) return d;
  } catch (_) {}
  return porDefecto;
}

// ══════════════════════════════════════════════════════════════
//  Segundo paso del inicio de sesion
// ══════════════════════════════════════════════════════════════

/// Pide el codigo de la app autenticadora (o un codigo de respaldo).
/// Devuelve los datos del usuario con su token, o null si se cancela.
Future<Map<String, dynamic>?> pedirCodigoDosPasos(
  BuildContext context, {
  required String apiBase,
  required String token2fa,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CodigoLoginDialog(apiBase: apiBase, token2fa: token2fa),
  );
}

class _CodigoLoginDialog extends StatefulWidget {
  final String apiBase;
  final String token2fa;
  const _CodigoLoginDialog({required this.apiBase, required this.token2fa});

  @override
  State<_CodigoLoginDialog> createState() => _CodigoLoginDialogState();
}

class _CodigoLoginDialogState extends State<_CodigoLoginDialog> {
  final _ctrl = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _verificar() async {
    final codigo = _ctrl.text.trim();
    if (codigo.isEmpty) {
      setState(() => _error = 'Escribe el codigo');
      return;
    }
    setState(() { _enviando = true; _error = null; });
    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBase}/auth/2fa/verificar'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token_2fa': widget.token2fa, 'codigo': codigo}),
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        Navigator.of(context)
            .pop(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
        return;
      }
      setState(() {
        _enviando = false;
        _error = _detalle(resp, 'No se pudo verificar el codigo.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _enviando = false; _error = 'No se pudo conectar al servidor.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Verificación en dos pasos'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Abre tu app autenticadora (Google Authenticator, Authy...) y escribe el '
              'codigo de 6 digitos. Si no tienes el celular, usa un codigo de respaldo.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              enabled: !_enviando,
              keyboardType: TextInputType.visiblePassword,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 3),
              decoration: InputDecoration(
                labelText: 'Codigo',
                prefixIcon: Icon(Icons.shield_outlined, size: 18),
              ),
              onSubmitted: (_) => _verificar(),
            ),
            if (_error != null) ...[
              SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.of(context).pop(),
          child: Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando ? null : _verificar,
          child: _enviando
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accentOnAccent))
              : Text('Verificar'),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Activar / desactivar desde la cuenta
// ══════════════════════════════════════════════════════════════

Future<void> mostrarVerificacionDosPasos(BuildContext context, {required String apiBase}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DosPasosDialog(apiBase: apiBase),
  );
}

enum _Paso { cargando, inactivo, qr, respaldo, activo }

class _DosPasosDialog extends StatefulWidget {
  final String apiBase;
  const _DosPasosDialog({required this.apiBase});

  @override
  State<_DosPasosDialog> createState() => _DosPasosDialogState();
}

class _DosPasosDialogState extends State<_DosPasosDialog> {
  final _codigoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  _Paso _paso = _Paso.cargando;
  bool _enviando = false;
  String? _error;
  String _secreto = '';
  String _uri = '';
  List<String> _codigos = [];
  int _restantes = 0;

  static const _json = {'Content-Type': 'application/json'};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await http.get(Uri.parse('${widget.apiBase}/auth/2fa/estado'));
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() { _paso = _Paso.inactivo; _error = _detalle(r, 'No se pudo consultar el estado.'); });
        return;
      }
      final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _paso = d['activo'] == true ? _Paso.activo : _Paso.inactivo;
        _restantes = (d['codigos_respaldo_restantes'] as int?) ?? 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _paso = _Paso.inactivo; _error = 'No se pudo conectar al servidor.'; });
    }
  }

  Future<void> _llamar(Future<void> Function() accion) async {
    setState(() { _enviando = true; _error = null; });
    try {
      await accion();
    } catch (_) {
      if (mounted) _error = 'No se pudo conectar al servidor.';
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _preparar() => _llamar(() async {
        final r = await http.post(Uri.parse('${widget.apiBase}/auth/2fa/preparar'));
        if (r.statusCode != 200) {
          _error = _detalle(r, 'No se pudo generar el codigo QR.');
          return;
        }
        final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _secreto = d['secreto'] as String;
        _uri = d['uri'] as String;
        _codigoCtrl.clear();
        _paso = _Paso.qr;
      });

  Future<void> _activar() => _llamar(() async {
        final r = await http.post(
          Uri.parse('${widget.apiBase}/auth/2fa/activar'),
          headers: _json,
          body: jsonEncode({'codigo': _codigoCtrl.text.trim()}),
        );
        if (r.statusCode != 200) {
          _error = _detalle(r, 'No se pudo activar.');
          return;
        }
        final d = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        _codigos = (d['codigos_respaldo'] as List).cast<String>();
        _restantes = _codigos.length;
        _paso = _Paso.respaldo;
      });

  Future<void> _desactivar() => _llamar(() async {
        final r = await http.post(
          Uri.parse('${widget.apiBase}/auth/2fa/desactivar'),
          headers: _json,
          body: jsonEncode({'password': _passCtrl.text, 'codigo': _codigoCtrl.text.trim()}),
        );
        if (r.statusCode != 200) {
          _error = _detalle(r, 'No se pudo desactivar.');
          return;
        }
        _passCtrl.clear();
        _codigoCtrl.clear();
        _paso = _Paso.inactivo;
      });

  Widget _texto(String t) =>
      Text(t, style: TextStyle(color: AppColors.textMuted, fontSize: 13));

  Widget _campoCodigo({String label = 'Codigo de 6 digitos', VoidCallback? alEnviar}) => TextField(
        controller: _codigoCtrl,
        enabled: !_enviando,
        autofocus: true,
        keyboardType: TextInputType.visiblePassword,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 18, letterSpacing: 3),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(Icons.pin_outlined, size: 18)),
        onSubmitted: alEnviar == null ? null : (_) => alEnviar(),
      );

  Widget _cuerpo() {
    switch (_paso) {
      case _Paso.cargando:
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        );
      case _Paso.inactivo:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _texto('Protege tu cuenta con un segundo paso: ademas de tu contraseña, se '
                'pedira un codigo de 6 digitos que cambia cada 30 segundos y que se genera '
                'en tu celular con una app como Google Authenticator o Authy.'),
            SizedBox(height: 10),
            Text('Estado: desactivada',
                style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
          ],
        );
      case _Paso.qr:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _texto('1. En la app autenticadora elige "Escanear codigo QR".'),
            SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: QrImageView(data: _uri, size: 180, backgroundColor: Colors.white),
              ),
            ),
            SizedBox(height: 10),
            _texto('¿No puedes escanear? Escribe esta clave en la app:'),
            SizedBox(height: 4),
            SelectableText(_secreto,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1)),
            SizedBox(height: 12),
            _texto('2. Escribe el codigo que muestra la app para confirmar:'),
            SizedBox(height: 6),
            _campoCodigo(alEnviar: _activar),
          ],
        );
      case _Paso.respaldo:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Verificacion en dos pasos activada',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            _texto('Guarda estos codigos de respaldo en un lugar seguro. Cada uno sirve '
                'una sola vez si pierdes el celular. No se volveran a mostrar.'),
            SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _codigos.join('\n'),
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, height: 1.6, letterSpacing: 1.5),
              ),
            ),
            SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: _codigos.join('\n'))),
                icon: Icon(Icons.copy_rounded, size: 16),
                label: Text('Copiar codigos'),
              ),
            ),
          ],
        );
      case _Paso.activo:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Estado: activada',
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            _texto('Codigos de respaldo disponibles: $_restantes'),
            SizedBox(height: 14),
            _texto('Para desactivarla escribe tu contraseña y un codigo de la app '
                '(o uno de respaldo):'),
            SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              enabled: !_enviando,
              obscureText: true,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                  labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline_rounded, size: 17)),
            ),
            SizedBox(height: 10),
            _campoCodigo(label: 'Codigo', alEnviar: _desactivar),
          ],
        );
    }
  }

  List<Widget> _acciones() {
    final cerrar = TextButton(
      onPressed: _enviando ? null : () => Navigator.of(context).pop(),
      child: Text(_paso == _Paso.respaldo ? 'Listo' : 'Cerrar'),
    );
    Widget boton(String texto, VoidCallback f, {bool peligro = false}) => FilledButton(
          style: peligro
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger, foregroundColor: AppColors.onDanger)
              : null,
          onPressed: _enviando ? null : f,
          child: _enviando
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: peligro ? AppColors.onDanger : AppColors.accentOnAccent))
              : Text(texto),
        );
    switch (_paso) {
      case _Paso.cargando:
        return [cerrar];
      case _Paso.inactivo:
        return [cerrar, boton('Activar', _preparar)];
      case _Paso.qr:
        return [cerrar, boton('Confirmar', _activar)];
      case _Paso.respaldo:
        return [cerrar];
      case _Paso.activo:
        return [cerrar, boton('Desactivar', _desactivar, peligro: true)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Verificación en dos pasos'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cuerpo(),
              if (_error != null) ...[
                SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: _acciones(),
    );
  }
}
