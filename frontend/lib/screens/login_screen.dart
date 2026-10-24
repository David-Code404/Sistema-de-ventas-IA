import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../screens/admin_shell.dart';
import '../screens/cajero_shell.dart';
import '../screens/cliente_shell.dart';
import '../theme/app_colors.dart';

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

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
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

      if (resp.statusCode == 401) {
        setState(() { _cargando = false; _error = 'Usuario o contrasena incorrectos.'; });
        return;
      }
      if (resp.statusCode != 200) {
        setState(() { _cargando = false; _error = 'Error del servidor. Intenta de nuevo.'; });
        return;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      Session.iniciar(
        id: data['id'] as int,
        u:  data['username'] as String,
        r:  data['rol'] as String,
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

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destino),
      );
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
                    _buildCard(),
                  ],
                ),
              ),
            ),
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
            Text('Usuario',
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
                hintText: 'Ingresa tu usuario',
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
                            strokeWidth: 2, color: Colors.white),
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