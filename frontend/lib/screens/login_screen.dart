import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../screens/admin_shell.dart';
import '../screens/cajero_shell.dart';
import '../screens/cliente_shell.dart';
import '../screens/registro_cliente_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/boton_modo_tema.dart';

class LoginScreen extends StatefulWidget {
  final String apiBase;

  LoginScreen({super.key, required this.apiBase});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _userCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  bool  _ocultarPass = true;
  bool  _cargando    = false;
  String? _error;

  // Segundo factor por correo (HU-24): tras la contrasena se pide el codigo enviado al correo.
  final _codigoCtrl  = TextEditingController();
  final _correoCtrl  = TextEditingController();
  String? _reto;            // identifica este inicio de sesion; null = aun en usuario/contrasena
  bool    _faltaCorreo = false;
  String? _correoMasc;      // correo al que se envio el codigo, ocultando parte
  int     _espera = 0;      // segundos para poder pedir otro codigo
  Timer?  _reloj;

  @override
  void dispose() {
    _reloj?.cancel();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _codigoCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  String _mensajeDe(http.Response resp, String porDefecto) {
    try {
      final d = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['detail'];
      if (d is String && d.isNotEmpty) return d;
    } catch (_) {}
    return porDefecto;
  }

  void _iniciarEspera() {
    _reloj?.cancel();
    setState(() => _espera = 30);
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _espera <= 1) {
        t.cancel();
        if (mounted) setState(() => _espera = 0);
        return;
      }
      setState(() => _espera--);
    });
  }

  void _volverAlInicio() {
    _reloj?.cancel();
    setState(() {
      _reto = null; _faltaCorreo = false; _correoMasc = null; _espera = 0;
      _error = null; _cargando = false;
      _codigoCtrl.clear(); _correoCtrl.clear(); _passCtrl.clear();
    });
  }

  Future<void> _post(String ruta, Map<String, dynamic> cuerpo,
      void Function(Map<String, dynamic> datos) alExito) async {
    setState(() { _cargando = true; _error = null; });
    try {
      final resp = await http
          .post(Uri.parse('${widget.apiBase}$ruta'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode(cuerpo))
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        setState(() => _cargando = false);
        alExito(jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
        return;
      }
      final mensaje = _mensajeDe(resp, 'Error del servidor (${resp.statusCode}).');
      // el inicio de sesion expiro: volver a empezar
      if (resp.statusCode == 401 && mensaje.contains('expiro')) {
        _volverAlInicio();
      }
      setState(() { _cargando = false; _error = mensaje; });
    } on TimeoutException {
      if (mounted) setState(() { _cargando = false; _error = 'El servidor tarda en responder. Intenta de nuevo.'; });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; _error = 'No se pudo conectar al servidor.'; });
    }
  }

  void _enviarCorreoNuevo() {
    final t = _correoCtrl.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
      setState(() => _error = 'Correo no valido (ejemplo: nombre@correo.com).');
      return;
    }
    _post('/auth/2fa/correo', {'reto': _reto, 'correo': t}, (d) {
      setState(() { _faltaCorreo = false; _correoMasc = d['correo'] as String?; });
      _iniciarEspera();
    });
  }

  void _verificarCodigo() {
    final c = _codigoCtrl.text.trim();
    if (c.length != 6) {
      setState(() => _error = 'El codigo tiene 6 digitos.');
      return;
    }
    _post('/auth/2fa/verificar', {'reto': _reto, 'codigo': c}, _entrar);
  }

  void _reenviarCodigo() {
    _post('/auth/2fa/reenviar', {'reto': _reto}, (d) {
      setState(() { _correoMasc = d['correo'] as String?; _codigoCtrl.clear(); });
      _iniciarEspera();
    });
  }

  void _entrar(Map<String, dynamic> data) {
    Session.iniciar(
      id: data['id'] as int,
      u:  data['username'] as String,
      r:  data['rol'] as String,
      datosCliente: (data['cliente'] as Map?)?.cast<String, dynamic>(),
    );
    if (!mounted) return;
    Widget destino;
    switch (data['rol'] as String) {
      case 'administrador':
        destino = AdminShell(apiBase: widget.apiBase);
        break;
      case 'cajero':
        destino = CajeroShell(apiBase: widget.apiBase);
        break;
      default:
        destino = ClienteShell(apiBase: widget.apiBase);
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => destino));
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _cargando = true; _error = null; });

    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBase}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': _userCtrl.text.trim(),
          'password': _passCtrl.text,
        }),
      );

      if (resp.statusCode == 401 || resp.statusCode == 429) {
        // 401: credenciales incorrectas (con los intentos que quedan). 429: bloqueo temporal (HU-24 1320).
        var mensaje = resp.statusCode == 429
            ? 'Demasiados intentos fallidos. Intenta de nuevo en unos minutos.'
            : 'Usuario o contrasena incorrectos.';
        try {
          final detalle = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['detail'];
          if (detalle is String && detalle.isNotEmpty) mensaje = detalle;
        } catch (_) {}
        setState(() { _cargando = false; _error = mensaje; });
        return;
      }
      if (resp.statusCode != 200) {
        setState(() { _cargando = false; _error = 'Error del servidor. Intenta de nuevo.'; });
        return;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      if (data['requiere_2fa'] == true) {
        setState(() {
          _cargando = false;
          _reto = data['reto'] as String;
          _faltaCorreo = data['falta_correo'] == true;
          _correoMasc = data['correo'] as String?;
          _codigoCtrl.clear();
        });
        if (!_faltaCorreo) _iniciarEspera();
        return;
      }
      _entrar(data);
    } catch (_) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo conectar al servidor.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.4),
                  radius: 1.2,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.06),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogo(),
                    SizedBox(height: 40),
                    _reto == null ? _buildCard() : _buildCardSegundoFactor(),
                    SizedBox(height: 18),
                    if (_reto == null) _buildCrearCuenta(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(child: BotonModoTema()),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.15),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(Icons.storefront_rounded,
              color: AppColors.accent, size: 38),
        ),
        SizedBox(height: 20),
        Text(
          'Caja Registradora IA',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Inicia sesion para acceder al sistema',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCardSegundoFactor() {
    final pideCorreo = _faltaCorreo;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 40, offset: Offset(0, 16))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.verified_user_outlined, color: AppColors.accent, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text('Verificacion en dos pasos',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ]),
          SizedBox(height: 8),
          Text(
            pideCorreo
                ? 'Tu rol exige verificar el inicio de sesion por correo. Escribe tu correo y te enviamos un codigo.'
                : 'Te enviamos un codigo de 6 digitos a ${_correoMasc ?? 'tu correo'}. Vale 5 minutos y se usa una sola vez.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          SizedBox(height: 18),
          if (pideCorreo)
            TextField(
              controller: _correoCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Correo',
                prefixIcon: Icon(Icons.mail_outline, size: 17),
              ),
              onSubmitted: (_) => _cargando ? null : _enviarCorreoNuevo(),
            )
          else
            TextField(
              controller: _codigoCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 8),
              decoration: InputDecoration(counterText: '', hintText: '000000'),
              onSubmitted: (_) => _cargando ? null : _verificarCodigo(),
            ),
          if (_error != null) ...[
            SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 13))),
              ]),
            ),
          ],
          SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _cargando ? null : (pideCorreo ? _enviarCorreoNuevo : _verificarCodigo),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: AppColors.accent,
              ),
              child: _cargando
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentOnAccent))
                  : Text(pideCorreo ? 'Enviar codigo' : 'Verificar',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.accentOnAccent)),
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: _cargando ? null : _volverAlInicio, child: Text('Volver')),
              if (!pideCorreo)
                TextButton(
                  onPressed: (_cargando || _espera > 0) ? null : _reenviarCodigo,
                  child: Text(_espera > 0 ? 'Reenviar en ${_espera}s' : 'Reenviar codigo'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCrearCuenta() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('¿Eres cliente y no tienes cuenta?',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        TextButton(
          onPressed: _cargando
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RegistroClienteScreen(apiBase: widget.apiBase))),
          child: Text('Crear cuenta',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Usuario o correo',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
            SizedBox(height: 8),
            TextFormField(
              controller: _userCtrl,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ingresa tu usuario o correo',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(10),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_outline_rounded,
                      color: AppColors.accent, size: 16),
                ),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              onFieldSubmitted: (_) => _login(),
            ),
            SizedBox(height: 20),

            Text('Contrasena',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
            SizedBox(height: 8),
            TextFormField(
              controller: _passCtrl,
              obscureText: _ocultarPass,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ingresa tu contrasena',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(10),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.lock_outline_rounded,
                      color: AppColors.accent, size: 16),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _ocultarPass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  onPressed: () =>
                      setState(() => _ocultarPass = !_ocultarPass),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Campo requerido' : null,
              onFieldSubmitted: (_) => _login(),
            ),

            if (_error != null) ...[
              SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: AppColors.danger, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 24),

            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _cargando ? null : _login,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  backgroundColor: AppColors.accent,
                ),
                child: _cargando
                    ? SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentOnAccent),
                      )
                    : Text('Ingresar',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentOnAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}