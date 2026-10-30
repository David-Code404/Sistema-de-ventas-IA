import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/categoria.dart';
import '../models/producto.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

class EditarProductoScreen extends StatefulWidget {
  final String apiBase;
  final Producto producto;

  EditarProductoScreen({
    super.key,
    required this.apiBase,
    required this.producto,
  });

  @override
  State<EditarProductoScreen> createState() => _EditarProductoScreenState();
}

class _EditarProductoScreenState extends State<EditarProductoScreen> {
  final _formKey        = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _precioCtrl;
  late final TextEditingController _stockMinimoCtrl;

  List<Categoria> _categorias    = [];
  int?            _categoriaSelec;
  bool            _cargandoCats  = true;

  // Imagen
  Uint8List? _imagenBytes;
  String?    _imagenNombre;
  bool       _imagenCargada = false;

  // Estado guardado
  bool    _guardando = false;
  bool    _guardado  = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombreCtrl      = TextEditingController(text: widget.producto.nombre);
    _precioCtrl      = TextEditingController(text: widget.producto.precio.toStringAsFixed(2));
    _stockMinimoCtrl = TextEditingController(text: '${widget.producto.stockMinimo}');
    _categoriaSelec  = widget.producto.categoriaId;
    _cargarCategorias();
    _cargarImagenActual();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _stockMinimoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final resp = await http.get(Uri.parse('${widget.apiBase}/categorias'));
      if (resp.statusCode != 200) return;
      final lista = jsonDecode(resp.body) as List;
      if (!mounted) return;
      setState(() {
        _categorias   = lista.map((e) => Categoria.fromJson(e as Map<String, dynamic>)).toList();
        _cargandoCats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoCats = false);
    }
  }

  Future<void> _cargarImagenActual() async {
    try {
      final resp = await http.get(
        Uri.parse('${widget.apiBase}/productos/${widget.producto.id}/imagen'),
      );
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _imagenBytes   = resp.bodyBytes;
          _imagenCargada = true;
        });
      }
    } catch (_) {
      // El producto aun no tiene imagen, no es error
    }
  }

  Future<void> _seleccionarImagen() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final archivo = result.files.first;
    if (!mounted) return;
    setState(() {
      _imagenBytes   = archivo.bytes;
      _imagenNombre  = archivo.name;
      _imagenCargada = true;
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaSelec == null) {
      setState(() => _error = 'Selecciona una categoria.');
      return;
    }

    setState(() { _guardando = true; _error = null; });

    try {
      // 1. Actualizar datos del producto (incluye stock_minimo)
      final resp = await http.put(
        Uri.parse('${widget.apiBase}/productos/${widget.producto.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre':       _nombreCtrl.text.trim(),
          'precio':       double.parse(_precioCtrl.text.trim()),
          'categoria_id': _categoriaSelec,
          'stock_minimo': int.parse(_stockMinimoCtrl.text.trim()),
        }),
      );
      if (resp.statusCode != 200) throw Exception('Error ${resp.statusCode}');

      // 2. Subir imagen si seleccionaron una nueva
      if (_imagenBytes != null && _imagenNombre != null) {
        final ext     = _imagenNombre!.split('.').last.toLowerCase();
        final uri     = Uri.parse('${widget.apiBase}/productos/${widget.producto.id}/imagen');
        final request = http.MultipartRequest('POST', uri);
        request.files.add(http.MultipartFile.fromBytes(
          'imagen',
          _imagenBytes!,
          filename: _imagenNombre!,
          contentType: MediaType('image', ext),
        ));
        await request.send();
      }

      if (!mounted) return;
      setState(() { _guardando = false; _guardado = true; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _guardando = false; _error = 'No se pudo guardar: $e'; });
    }
  }

  Color _colorCategoria() {
    if (_categoriaSelec == null) return AppColors.accent;
    for (final c in _categorias) {
      if (c.id == _categoriaSelec) {
        return AppColors.hexToColor(c.color) ?? AppColors.tagColorFor(_categoriaSelec!);
      }
    }
    return AppColors.tagColorFor(_categoriaSelec!);
  }

  String _nombreCategoria() {
    for (final c in _categorias) {
      if (c.id == _categoriaSelec) return c.nombre;
    }
    return 'Sin categoria';
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.catalogo,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Editar producto'),
        ),
        body: BoundedContent(
          maxWidth: 700,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _buildHero(),
              SizedBox(height: 24),
              _buildFormulario(),
              if (_error != null) ...[
                SizedBox(height: 12),
                _buildError(_error!),
              ],
              if (_guardado) ...[
                SizedBox(height: 12),
                _buildExito(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero: imagen grande + badge de categoría ────────────────
  Widget _buildHero() {
    final color = _colorCategoria();

    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo degradado sutil
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: 0.12),
                  AppColors.surface,
                ],
              ),
            ),
          ),

          // Imagen o placeholder
          if (_imagenBytes != null)
            Image.memory(
              _imagenBytes!,
              fit: BoxFit.contain,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 56,
                    color: color.withValues(alpha: 0.4),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Sin imagen de referencia',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // Badge de categoria arriba a la izquierda
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined, color: color, size: 12),
                  SizedBox(width: 5),
                  Text(
                    _cargandoCats ? '...' : _nombreCategoria(),
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),

          // Precio arriba a la derecha
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Bs. ${widget.producto.precio.toStringAsFixed(2)}',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),

          // Botón cambiar imagen abajo centrado
          Positioned(
            bottom: 14,
            left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _seleccionarImagen,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _imagenCargada
                            ? Icons.edit_outlined
                            : Icons.add_photo_alternate_outlined,
                        color: color,
                        size: 15,
                      ),
                      SizedBox(width: 6),
                      Text(
                        _imagenCargada ? 'Cambiar imagen' : 'Agregar imagen',
                        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Formulario ──────────────────────────────────────────────
  Widget _buildFormulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSeccion(
            'Informacion del producto',
            Icons.inventory_2_outlined,
            [
              TextFormField(
                controller: _nombreCtrl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Nombre del producto',
                  prefixIcon: Icon(Icons.label_outline, size: 17),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'El nombre es obligatorio' : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _precioCtrl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Precio (Bs.)',
                  prefixIcon: Icon(Icons.attach_money_rounded, size: 17),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'El precio es obligatorio';
                  final n = double.tryParse(v.trim());
                  if (n == null || n <= 0) return 'Precio invalido';
                  return null;
                },
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _stockMinimoCtrl,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Stock mínimo',
                  hintText: 'Ej. 5',
                  prefixIcon: Icon(Icons.warning_amber_rounded, size: 17),
                  helperText: 'Alerta cuando el stock baje de este valor',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 0) return 'Debe ser 0 o mayor';
                  return null;
                },
              ),
              SizedBox(height: 12),
              _cargandoCats
                  ? Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : DropdownButtonFormField<int>(
                      value: _categoriaSelec,
                      dropdownColor: AppColors.surfaceAlt,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Categoria',
                        prefixIcon: Icon(Icons.category_outlined, size: 17),
                      ),
                      items: _categorias
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre)))
                          .toList(),
                      onChanged: (v) => setState(() => _categoriaSelec = v),
                      validator: (v) => v == null ? 'Selecciona una categoria' : null,
                    ),
            ],
          ),
          SizedBox(height: 24),

          // Botón guardar
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentOnAccent),
                    )
                  : Icon(Icons.save_outlined),
              label: Text(
                _guardando ? 'Guardando...' : 'Guardar cambios',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccion(String titulo, IconData icono, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icono, color: AppColors.accent, size: 15),
            SizedBox(width: 7),
            Text(
              titulo.toUpperCase(),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildError(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(msg, style: TextStyle(color: AppColors.danger, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildExito() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: AppColors.accent, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Producto actualizado correctamente.',
              style: TextStyle(color: AppColors.accent, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Volver'),
          ),
        ],
      ),
    );
  }
}