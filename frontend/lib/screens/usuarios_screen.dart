import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

const _roles = ['administrador', 'cajero', 'cliente'];

String _etiquetaRol(String rol) => switch (rol) {
      'administrador' => 'Administrador',
      'cajero' => 'Cajero',
      _ => 'Cliente',
    };

Color _colorRol(String rol) => switch (rol) {
      'administrador' => AppColors.accent,
      'cajero' => AppColors.warning,
      _ => Color(0xFF38BDF8),
    };

IconData _iconoRol(String rol) => switch (rol) {
      'administrador' => Icons.admin_panel_settings_outlined,
      'cajero' => Icons.point_of_sale_outlined,
      _ => Icons.person_outline_rounded,
    };

class _Usuario {
  final int id;
  final String username;
  final String rol;

  _Usuario({required this.id, required this.username, required this.rol});

  factory _Usuario.fromJson(Map<String, dynamic> j) => _Usuario(
        id: j['id'] as int,
        username: j['username'] as String,
        rol: j['rol'] as String,
      );
}

class UsuariosScreen extends StatefulWidget {
  final String apiBase;

  UsuariosScreen({super.key, required this.apiBase});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<_Usuario> _usuarios = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http.get(Uri.parse('${widget.apiBase}/usuarios'));
      if (resp.statusCode != 200) throw Exception('Backend: ${resp.statusCode}');
      final lista = jsonDecode(resp.body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _usuarios = lista
            .map((e) => _Usuario.fromJson(e as Map<String, dynamic>))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los usuarios: $e';
      });
    }
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

  Future<void> _agregar() async {
    final datos = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _DialogNuevoUsuario(),
    );
    if (datos == null) return;

    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBase}/usuarios'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(datos),
      );
      if (resp.statusCode != 201) {
        _aviso(_detalle(resp), error: true);
        return;
      }
      _aviso('Usuario "${datos['username']}" creado.');
      _cargar();
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Solo el administrador puede ver esta pantalla.
    if (!Session.esAdmin) {
      return Scaffold(
        body: Center(child: Text('No tienes permiso para ver esta sección.')),
      );
    }

    return AppShell(
      current: AppSection.usuarios,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text('Usuarios')),
        body: BoundedContent(
          maxWidth: 780,
          child: _cargando && _usuarios.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildEncabezado(),
                      SizedBox(height: 16),
                      _buildLista(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    final icono = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(9)),
      child: Icon(Icons.group_outlined, color: AppColors.accent, size: 18),
    );
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Usuarios',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        Text(
          '${_usuarios.length} usuarios registrados',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
    final boton = FilledButton.icon(
      onPressed: _agregar,
      icon: Icon(Icons.person_add_alt_1_rounded, size: 17),
      label: Text('Agregar usuario'),
    );

    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth >= 520) {
        return Row(children: [
          icono,
          SizedBox(width: 12),
          Expanded(child: titulo),
          boton,
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [icono, SizedBox(width: 12), Expanded(child: titulo)]),
          SizedBox(height: 10),
          boton,
        ],
      );
    });
  }

  Widget _buildLista() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _cargar,
                icon: Icon(Icons.refresh_rounded, size: 16),
                label: Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_usuarios.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aún no hay usuarios.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return Column(children: _usuarios.map(_fila).toList());
  }

  Widget _fila(_Usuario u) {
    final color = _colorRol(u.rol);
    final esYo = u.username == Session.username;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconoRol(u.rol), color: color, size: 20),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                esYo ? '${u.username}  (tú)' : u.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(_etiquetaRol(u.rol),
                  style: TextStyle(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Diálogo: nuevo usuario ────────────────────────────────────
class _DialogNuevoUsuario extends StatefulWidget {
  const _DialogNuevoUsuario();

  @override
  State<_DialogNuevoUsuario> createState() => _DialogNuevoUsuarioState();
}

class _DialogNuevoUsuarioState extends State<_DialogNuevoUsuario> {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  String _rol = 'cajero';
  bool _ocultar = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text('Agregar usuario',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _userCtrl,
                  autofocus: true,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 17),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'El usuario es obligatorio';
                    if (!RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(t)) {
                      return '3 a 50 caracteres: letras, números, . - _';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _ocultar,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon:
                        Icon(Icons.lock_outline_rounded, size: 17),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _ocultar
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18),
                      onPressed: () => setState(() => _ocultar = !_ocultar),
                    ),
                  ),
                  validator: (v) {
                    if ((v ?? '').length < 6) return 'Mínimo 6 caracteres';
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _pass2Ctrl,
                  obscureText: _ocultar,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Confirmar contraseña',
                    prefixIcon: Icon(Icons.lock_reset_rounded, size: 17),
                  ),
                  validator: (v) =>
                      v != _passCtrl.text ? 'Las contraseñas no coinciden' : null,
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _rol,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.badge_outlined, size: 17),
                  ),
                  items: _roles
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(_etiquetaRol(r))))
                      .toList(),
                  onChanged: (v) => setState(() => _rol = v ?? _rol),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'username': _userCtrl.text.trim(),
              'password': _passCtrl.text,
              'rol': _rol,
            });
          },
          child: Text('Crear usuario'),
        ),
      ],
    );
  }
}
