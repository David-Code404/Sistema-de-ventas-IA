import 'dart:async';
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
      _ => AppColors.info,
    };

IconData _iconoRol(String rol) => switch (rol) {
      'administrador' => Icons.admin_panel_settings_outlined,
      'cajero' => Icons.point_of_sale_outlined,
      _ => Icons.person_outline_rounded,
    };

class _Usuario {
  final int id;
  final String username;
  final String nombre;
  final String? correo;
  final String rol;
  final bool activo;

  _Usuario({
    required this.id,
    required this.username,
    required this.nombre,
    required this.correo,
    required this.rol,
    required this.activo,
  });

  factory _Usuario.fromJson(Map<String, dynamic> j) => _Usuario(
        id: j['id'] as int,
        username: j['username'] as String,
        nombre: (j['nombre'] ?? j['username']) as String,
        correo: j['correo'] as String?,
        rol: j['rol'] as String,
        activo: j['activo'] != false,
      );
}

class UsuariosScreen extends StatefulWidget {
  final String apiBase;

  UsuariosScreen({super.key, required this.apiBase});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;
  String? _rolFiltro;
  List<_Usuario> _usuarios = [];
  Map<String, String> _correos2fa = {}; // id de usuario -> correo del segundo factor
  bool _cargando = true;
  bool _cargadoAlgunaVez = false;
  String? _error;

  // El backend comprueba que quien llama sea un administrador activo.
  Map<String, String> get _headers =>
      {'X-Usuario-Id': '${Session.usuarioId}'};
  Map<String, String> get _headersJson =>
      {..._headers, 'Content-Type': 'application/json'};

  bool get _hayFiltros =>
      _busquedaCtrl.text.trim().isNotEmpty || _rolFiltro != null;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _alEscribir(String _) {
    setState(() {}); // actualiza el botón de limpiar
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 350), _cargar);
  }

  void _elegirRol(String? rol) {
    if (_rolFiltro == rol) return;
    setState(() => _rolFiltro = rol);
    _cargar();
  }

  void _limpiarFiltros() {
    _busquedaCtrl.clear();
    setState(() => _rolFiltro = null);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final busqueda = _busquedaCtrl.text.trim();
      final uri = Uri.parse('${widget.apiBase}/usuarios').replace(
        queryParameters: {
          if (busqueda.isNotEmpty) 'busqueda': busqueda,
          if (_rolFiltro != null) 'rol': _rolFiltro!,
        },
      );
      final resp = await http.get(uri, headers: _headers);
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw Exception(_detalle(resp));
      }
      if (resp.statusCode != 200) throw Exception('Backend: ${resp.statusCode}');
      final lista = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      var correos = <String, String>{};
      try {
        final r2 = await http.get(Uri.parse('${widget.apiBase}/usuarios/correos-2fa'), headers: _headers);
        if (r2.statusCode == 200) {
          correos = (jsonDecode(utf8.decode(r2.bodyBytes)) as Map).map((k, v) => MapEntry('$k', '$v'));
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _correos2fa = correos;
        _usuarios = lista
            .map((e) => _Usuario.fromJson(e as Map<String, dynamic>))
            .toList();
        _cargando = false;
        _cargadoAlgunaVez = true;
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
    final correo = (datos.remove('correo_2fa') ?? '').trim();

    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBase}/usuarios'),
        headers: _headersJson,
        body: jsonEncode(datos),
      );
      if (resp.statusCode != 201) {
        _aviso(_detalle(resp), error: true);
        return;
      }
      if (correo.isNotEmpty) {
        final nuevoId = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['id'];
        final r2 = await http.put(
          Uri.parse('${widget.apiBase}/usuarios/$nuevoId/correo-2fa'),
          headers: _headersJson,
          body: jsonEncode({'correo': correo}),
        );
        if (r2.statusCode != 200) {
          _aviso('Usuario creado, pero el correo no se guardo: ${_detalle(r2)}', error: true);
          _cargar();
          return;
        }
      }
      _aviso('Usuario "${datos['username']}" creado.');
      _cargar();
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  Future<void> _editar(_Usuario u) async {
    final cambios = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _DialogEditarUsuario(
        usuario: u,
        esYo: u.id == Session.usuarioId,
        correo2fa: _correos2fa['${u.id}'] ?? '',
      ),
    );
    if (cambios == null) return;
    final correo = cambios.remove('correo_2fa');

    try {
      if (cambios.isNotEmpty) {
        final resp = await http.put(
          Uri.parse('${widget.apiBase}/usuarios/${u.id}'),
          headers: _headersJson,
          body: jsonEncode(cambios),
        );
        if (resp.statusCode != 200) {
          _aviso(_detalle(resp), error: true);
          return;
        }
      }
      if (correo != null) {
        final r2 = await http.put(
          Uri.parse('${widget.apiBase}/usuarios/${u.id}/correo-2fa'),
          headers: _headersJson,
          body: jsonEncode({'correo': correo}),
        );
        if (r2.statusCode != 200) {
          _aviso(_detalle(r2), error: true);
          return;
        }
      }
      if (u.id == Session.usuarioId && cambios.containsKey('username')) {
        Session.username = cambios['username'];
      }
      _aviso('Usuario "${cambios['username'] ?? u.username}" actualizado.');
      _cargar();
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  Future<void> _cambiarEstado(_Usuario u) async {
    final activar = !u.activo;
    if (!activar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: Text('Desactivar usuario',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          content: Text(
              '"${u.nombre}" ya no podrá iniciar sesión. '
              'Puedes volver a activarlo cuando quieras.',
              style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Desactivar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      final resp = await http.patch(
        Uri.parse('${widget.apiBase}/usuarios/${u.id}/activo'),
        headers: _headersJson,
        body: jsonEncode({'activo': activar}),
      );
      if (resp.statusCode != 200) {
        _aviso(_detalle(resp), error: true);
        return;
      }
      _aviso(activar
          ? 'Usuario "${u.nombre}" activado.'
          : 'Usuario "${u.nombre}" desactivado.');
      _cargar();
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  Future<void> _eliminar(_Usuario u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text('Eliminar usuario',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text(
            '¿Eliminar a "${u.nombre}" para siempre? Esta acción no se puede deshacer. '
            'Si la cuenta ya tiene historial, mejor desactívala.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await http.delete(Uri.parse('${widget.apiBase}/usuarios/${u.id}'), headers: _headers);
      if (resp.statusCode != 200) {
        _aviso(_detalle(resp), error: true);
        return;
      }
      _aviso('Usuario "${u.nombre}" eliminado.');
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
          child: _cargando && !_cargadoAlgunaVez
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildEncabezado(),
                      SizedBox(height: 16),
                      _buildFiltros(),
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
          _hayFiltros
              ? '${_usuarios.length} ${_usuarios.length == 1 ? 'resultado' : 'resultados'}'
              : '${_usuarios.length} usuarios registrados',
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

  Widget _buildFiltros() {
    const opciones = <(String?, String)>[
      (null, 'Todos'),
      ('administrador', 'Administrador'),
      ('cajero', 'Cajero'),
      ('cliente', 'Cliente'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _busquedaCtrl,
          onChanged: _alEscribir,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Buscar por nombre o correo',
            prefixIcon: Icon(Icons.search_rounded, size: 18),
            suffixIcon: _busquedaCtrl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar búsqueda',
                    icon: Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _busquedaCtrl.clear();
                      setState(() {});
                      _cargar();
                    },
                  ),
          ),
        ),
        SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in opciones) _chipRol(o.$1, o.$2),
          ],
        ),
      ],
    );
  }

  Widget _chipRol(String? rol, String etiqueta) {
    final activo = _rolFiltro == rol;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _elegirRol(rol),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: activo
              ? AppColors.accent.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: activo
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border),
        ),
        child: Text(etiqueta,
            style: TextStyle(
                color: activo ? AppColors.accent : AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      ),
    );
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
          child: _hayFiltros
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No se encontraron usuarios con ese criterio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                    SizedBox(height: 10),
                    TextButton(
                      onPressed: _limpiarFiltros,
                      child: Text('Quitar filtros'),
                    ),
                  ],
                )
              : Text('Aún no hay usuarios.',
                  style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return Column(children: _usuarios.map(_fila).toList());
  }

  Widget _fila(_Usuario u) {
    final color = _colorRol(u.rol);
    final esYo = u.id == Session.usuarioId;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    esYo ? '${u.nombre}  (tú)' : u.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: u.activo
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                  ),
                  if (u.correo != null && u.correo != u.nombre)
                    Text(
                      u.correo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  if (_correos2fa['${u.id}'] != null)
                    Text(
                      '2FA: ${_correos2fa['${u.id}']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                ],
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
            SizedBox(width: 8),
            _chipEstado(u.activo),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              icon: Icon(Icons.more_vert_rounded,
                  size: 18, color: AppColors.textMuted),
              color: AppColors.surfaceAlt,
              onSelected: (accion) {
                if (accion == 'editar') _editar(u);
                if (accion == 'estado') _cambiarEstado(u);
                if (accion == 'eliminar') _eliminar(u);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'editar',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 17),
                    SizedBox(width: 10),
                    Text('Editar'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'estado',
                  // No puedes desactivar tu propia cuenta
                  enabled: !(esYo && u.activo),
                  child: Row(children: [
                    Icon(
                        u.activo
                            ? Icons.block_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 17),
                    SizedBox(width: 10),
                    Text(u.activo ? 'Desactivar' : 'Activar'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'eliminar',
                  // No puedes eliminar tu propia cuenta
                  enabled: !esYo,
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('Eliminar', style: TextStyle(color: AppColors.danger)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chipEstado(bool activo) {
  final color = activo ? AppColors.accent : AppColors.danger;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(activo ? 'Activo' : 'Inactivo',
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

Widget _campoCorreo2fa(TextEditingController ctrl) {
  return TextFormField(
    controller: ctrl,
    keyboardType: TextInputType.emailAddress,
    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
    decoration: InputDecoration(
      labelText: 'Correo para el código 2FA (opcional)',
      helperText: 'Ahí llega el código de verificación al iniciar sesión',
      prefixIcon: Icon(Icons.mail_outline, size: 17),
    ),
    validator: (v) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return null;
      if (t.length > 100 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
        return 'Correo no válido (ejemplo: nombre@correo.com)';
      }
      return null;
    },
  );
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
  final _correoCtrl = TextEditingController();
  String _rol = 'cajero';
  bool _ocultar = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    _correoCtrl.dispose();
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
                SizedBox(height: 12),
                _campoCorreo2fa(_correoCtrl),
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
              'correo_2fa': _correoCtrl.text.trim(),
            });
          },
          child: Text('Crear usuario'),
        ),
      ],
    );
  }
}

// ── Diálogo: editar usuario ───────────────────────────────────
class _DialogEditarUsuario extends StatefulWidget {
  final _Usuario usuario;
  final bool esYo;
  final String correo2fa;

  const _DialogEditarUsuario({required this.usuario, required this.esYo, this.correo2fa = ''});

  @override
  State<_DialogEditarUsuario> createState() => _DialogEditarUsuarioState();
}

class _DialogEditarUsuarioState extends State<_DialogEditarUsuario> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();
  late final TextEditingController _correoCtrl;
  late String _rol;
  bool _ocultar = true;

  @override
  void initState() {
    super.initState();
    _correoCtrl = TextEditingController(text: widget.correo2fa);
    _userCtrl = TextEditingController(text: widget.usuario.username);
    _rol = widget.usuario.rol;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _correoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text('Editar usuario',
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
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14),
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
                DropdownButtonFormField<String>(
                  value: _rol,
                  dropdownColor: AppColors.surfaceAlt,
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Rol',
                    prefixIcon: Icon(Icons.badge_outlined, size: 17),
                    helperText: widget.esYo
                        ? 'No puedes cambiar tu propio rol'
                        : null,
                  ),
                  items: _roles
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(_etiquetaRol(r))))
                      .toList(),
                  // Un administrador no puede quitarse su propio rol
                  onChanged: widget.esYo
                      ? null
                      : (v) => setState(() => _rol = v ?? _rol),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _ocultar,
                  style:
                      TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña (opcional)',
                    prefixIcon: Icon(Icons.lock_outline_rounded, size: 17),
                    helperText: 'Déjala vacía para no cambiarla',
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
                    final t = v ?? '';
                    if (t.isNotEmpty && t.length < 6) {
                      return 'Mínimo 6 caracteres';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                _campoCorreo2fa(_correoCtrl),
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
            // Solo se envía lo que cambió
            final cambios = <String, String>{};
            final usuario = _userCtrl.text.trim();
            if (usuario != widget.usuario.username) {
              cambios['username'] = usuario;
            }
            if (_rol != widget.usuario.rol) cambios['rol'] = _rol;
            if (_passCtrl.text.isNotEmpty) cambios['password'] = _passCtrl.text;
            if (_correoCtrl.text.trim() != widget.correo2fa) cambios['correo_2fa'] = _correoCtrl.text.trim();
            Navigator.pop(context, cambios.isEmpty ? null : cambios);
          },
          child: Text('Guardar cambios'),
        ),
      ],
    );
  }
}