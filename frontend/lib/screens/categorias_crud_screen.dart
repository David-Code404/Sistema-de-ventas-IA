import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/categoria.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

class CategoriasCrudScreen extends StatefulWidget {
  final String apiBase;

  CategoriasCrudScreen({super.key, required this.apiBase});

  @override
  State<CategoriasCrudScreen> createState() => _CategoriasCrudScreenState();
}

class _CategoriasCrudScreenState extends State<CategoriasCrudScreen> {
  List<Categoria> _categorias = [];
  Map<int, int> _productosPorCategoria = {};
  bool _cargando = true;
  String? _error;

  bool _formularioAbierto = false;
  Categoria? _categoriaEditando;
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _errorFormulario;
  bool _guardando = false;
  Color _colorSeleccionado = AppColors.categoriaPalette.first;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    setState(() => _cargando = true);
    try {
      final respuestas = await Future.wait([
        http.get(Uri.parse('${widget.apiBase}/categorias')),
        http.get(Uri.parse('${widget.apiBase}/productos')),
      ]);

      if (respuestas[0].statusCode != 200) {
        throw Exception('El backend respondió ${respuestas[0].statusCode}');
      }

      final lista = jsonDecode(respuestas[0].body) as List<dynamic>;
      final conteo = <int, int>{};
      if (respuestas[1].statusCode == 200) {
        final productos = jsonDecode(respuestas[1].body) as List<dynamic>;
        for (final p in productos) {
          final categoriaId = (p as Map<String, dynamic>)['categoria_id'];
          if (categoriaId is int) {
            conteo[categoriaId] = (conteo[categoriaId] ?? 0) + 1;
          }
        }
      }

      setState(() {
        _categorias = lista.map((e) => Categoria.fromJson(e as Map<String, dynamic>)).toList();
        _productosPorCategoria = conteo;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las categorías: $e';
      });
    }
  }

  Future<String?> _crearCategoria(String nombre, String descripcion, String color) async {
    final respuesta = await http.post(
      Uri.parse('${widget.apiBase}/categorias'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'descripcion': descripcion, 'color': color}),
    );
    if (respuesta.statusCode >= 400) {
      return _mensajeDeError(respuesta);
    }
    await _cargarCategorias();
    return null;
  }

  Future<String?> _editarCategoria(int id, String nombre, String descripcion, String color) async {
    final respuesta = await http.put(
      Uri.parse('${widget.apiBase}/categorias/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'descripcion': descripcion, 'color': color}),
    );
    if (respuesta.statusCode >= 400) {
      return _mensajeDeError(respuesta);
    }
    await _cargarCategorias();
    return null;
  }

  Future<void> _eliminarCategoria(Categoria categoria) async {
    final respuesta = await http.delete(Uri.parse('${widget.apiBase}/categorias/${categoria.id}'));
    if (respuesta.statusCode >= 400) {
      final mensaje = _mensajeDeError(respuesta);
      if (mounted && mensaje != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
      }
      return;
    }
    await _cargarCategorias();
  }

  String? _mensajeDeError(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
      final detalle = cuerpo['detail'];
      if (detalle is String) return detalle;
      if (detalle is List && detalle.isNotEmpty) {
        final primero = detalle.first;
        if (primero is Map && primero['msg'] != null) return primero['msg'].toString();
      }
    } catch (_) {
      // cuerpo no era JSON, se usa el mensaje genérico de abajo
    }
    return 'Ocurrió un error inesperado (${respuesta.statusCode})';
  }

  void _abrirCrear() {
    setState(() {
      _categoriaEditando = null;
      _nombreCtrl.clear();
      _descCtrl.clear();
      _colorSeleccionado = AppColors.categoriaPalette.first;
      _errorFormulario = null;
      _formularioAbierto = true;
    });
  }

  void _abrirEditar(Categoria categoria) {
    setState(() {
      _categoriaEditando = categoria;
      _nombreCtrl.text = categoria.nombre;
      _descCtrl.text = categoria.descripcion;
      _colorSeleccionado = AppColors.hexToColor(categoria.color) ?? AppColors.tagColorFor(categoria.id);
      _errorFormulario = null;
      _formularioAbierto = true;
    });
  }

  void _cerrarFormulario() {
    setState(() {
      _formularioAbierto = false;
      _errorFormulario = null;
    });
  }

  Future<void> _guardarFormulario() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _errorFormulario = null;
    });

    final categoria = _categoriaEditando;
    final colorHex = AppColors.colorToHex(_colorSeleccionado);
    final mensaje = categoria == null
        ? await _crearCategoria(_nombreCtrl.text.trim(), _descCtrl.text.trim(), colorHex)
        : await _editarCategoria(categoria.id, _nombreCtrl.text.trim(), _descCtrl.text.trim(), colorHex);

    if (!mounted) return;
    if (mensaje != null) {
      setState(() {
        _guardando = false;
        _errorFormulario = mensaje;
      });
    } else {
      setState(() {
        _guardando = false;
        _formularioAbierto = false;
      });
    }
  }

  void _confirmarEliminar(Categoria categoria) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
            SizedBox(width: 10),
            Text('Eliminar categoría'),
          ],
        ),
        content: Text('¿Seguro que quieres eliminar "${categoria.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _eliminarCategoria(categoria);
            },
            child: Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.categorias,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Categorías'),
          actions: [
            if (!_formularioAbierto)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: _abrirCrear,
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Nueva categoría'),
                ),
              ),
          ],
        ),
        body: BoundedContent(maxWidth: 1200, child: _buildContenido()),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return _EstadoVacio(
        icono: Icons.wifi_off_rounded,
        titulo: 'No se pudo conectar',
        subtitulo: _error!,
        accion: TextButton.icon(
          onPressed: _cargarCategorias,
          icon: Icon(Icons.refresh, size: 16),
          label: Text('Reintentar'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_formularioAbierto) ...[
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 640),
            child: _buildFormulario(),
          ),
          SizedBox(height: 16),
        ],
        Row(
          children: [
            Text(
              'Categorías creadas',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            SizedBox(width: 8),
            Text('${_categorias.length} categorías', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
        SizedBox(height: 10),
        if (_categorias.isEmpty)
          const _EstadoVacio(
            icono: Icons.category_outlined,
            titulo: 'Todavía no hay categorías',
            subtitulo: 'Usa el botón "Nueva categoría" para crear la primera.',
          )
        else
          _buildGrilla(),
      ],
    );
  }

  Widget _buildGrilla() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnas = constraints.maxWidth > 980 ? 3 : (constraints.maxWidth > 620 ? 2 : 1);
        final ancho = (constraints.maxWidth - (columnas - 1) * 12) / columnas;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _categorias.map((cat) {
            return SizedBox(width: ancho, child: _buildTarjeta(cat));
          }).toList(),
        );
      },
    );
  }

  Widget _buildFormulario() {
    final editando = _categoriaEditando != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editando ? 'Editar categoría' : 'Nueva categoría',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _nombreCtrl,
                    autofocus: true,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(labelText: 'Nombre', hintText: 'Ej. Cuidado personal'),
                    validator: (valor) {
                      if (valor == null || valor.trim().isEmpty) {
                        return 'El nombre no puede estar vacío';
                      }
                      if (valor.trim().length > 100) {
                        return 'Máximo 100 caracteres';
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Color', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    SizedBox(height: 10),
                    Row(
                      children: AppColors.categoriaPalette.map((color) {
                        final seleccionado = color.value == _colorSeleccionado.value;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => setState(() => _colorSeleccionado = color),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: seleccionado ? AppColors.textPrimary : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: seleccionado
                                  ? Icon(Icons.check, size: 14, color: AppColors.background)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              style: TextStyle(color: AppColors.textPrimary),
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Descripción (opcional)'),
            ),
            if (_errorFormulario != null) ...[
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorFormulario!, style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                ],
              ),
            ],
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _guardando ? null : _cerrarFormulario,
                  child: Text('Cancelar'),
                ),
                SizedBox(width: 8),
                FilledButton(
                  onPressed: _guardando ? null : _guardarFormulario,
                  child: _guardando
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentOnAccent),
                        )
                      : Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjeta(Categoria cat) {
    final color = AppColors.hexToColor(cat.color) ?? AppColors.tagColorFor(cat.id);
    final productos = _productosPorCategoria[cat.id] ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.label_rounded, color: color, size: 16),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '$productos productos',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _abrirEditar(cat),
                  icon: Icon(Icons.edit_outlined, size: 14),
                  label: Text('Editar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _confirmarEliminar(cat),
                  icon: Icon(Icons.delete_outline, size: 14),
                  label: Text('Eliminar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger.withValues(alpha: 0.15),
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: TextStyle(fontSize: 12),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Widget? accion;

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              child: Icon(icono, color: AppColors.textMuted, size: 26),
            ),
            SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              subtitulo,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            if (accion != null) ...[
              SizedBox(height: 16),
              accion!,
            ],
          ],
        ),
      ),
    );
  }
}