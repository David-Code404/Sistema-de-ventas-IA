import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/categoria.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

class AgregarProductoScreen extends StatefulWidget {
  final String apiBase;

  AgregarProductoScreen({super.key, required this.apiBase});

  @override
  State<AgregarProductoScreen> createState() => _AgregarProductoScreenState();
}

class _AgregarProductoScreenState extends State<AgregarProductoScreen> {
  final _nombreCtrl      = TextEditingController();
  final _precioCtrl      = TextEditingController();
  final _cantidadCtrl    = TextEditingController();
  final _stockMinimoCtrl = TextEditingController(text: '5');
  final _formKey         = GlobalKey<FormState>();

  List<Categoria> _categorias   = [];
  int?            _categoriaSelec;
  bool            _cargandoCats = true;

  // Imagen de referencia
  Uint8List? _imagenBytes;
  String?    _imagenNombre;

  _Estado _estado         = _Estado.formulario;
  String  _mensajeProceso = '';
  String? _error;
  int?    _productoNuevoId;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    _cantidadCtrl.dispose();
    _stockMinimoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final resp = await http.get(Uri.parse('${widget.apiBase}/categorias'));
      if (resp.statusCode != 200) throw Exception();
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
      _imagenBytes  = archivo.bytes;
      _imagenNombre = archivo.name;
    });
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoriaSelec == null) {
      _snack('Selecciona una categoria.');
      return;
    }

    setState(() {
      _estado         = _Estado.subiendo;
      _mensajeProceso = 'Guardando el producto...';
      _error          = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('${widget.apiBase}/productos'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nombre':       _nombreCtrl.text.trim(),
          'precio':       double.parse(_precioCtrl.text.trim().replaceAll(',', '.')),
          'cantidad':     int.tryParse(_cantidadCtrl.text.trim()) ?? 0,
          'categoria_id': _categoriaSelec,
          'stock_minimo': int.tryParse(_stockMinimoCtrl.text.trim()) ?? 5,
        }),
      );
      if (resp.statusCode != 201) {
        String detalle = 'Error ${resp.statusCode}';
        try {
          detalle = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['detail'].toString();
        } catch (_) {}
        throw Exception(detalle);
      }

      _productoNuevoId = (jsonDecode(resp.body) as Map<String, dynamic>)['producto_id'] as int?;
      if (_imagenBytes != null && _imagenNombre != null && _productoNuevoId != null) {
        await _subirImagen(_productoNuevoId!);
      }
      if (!mounted) return;
      setState(() {
        _estado         = _Estado.listo;
        _mensajeProceso = "Producto '${_nombreCtrl.text.trim()}' registrado correctamente.";
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _estado = _Estado.formulario;
        _error  = 'No se pudo guardar: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _subirImagen(int productoId) async {
    try {
      final ext     = _imagenNombre!.split('.').last.toLowerCase();
      final uri     = Uri.parse('${widget.apiBase}/productos/$productoId/imagen');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes(
        'imagen', _imagenBytes!,
        filename: _imagenNombre!,
        contentType: MediaType('image', ext),
      ));
      await request.send();
    } catch (_) {}
  }

  void _reiniciar() {
    setState(() {
      _nombreCtrl.clear();
      _precioCtrl.clear();
      _cantidadCtrl.clear();
      _stockMinimoCtrl.text = '5';
      _categoriaSelec  = null;
      _imagenBytes     = null;
      _imagenNombre    = null;
      _estado          = _Estado.formulario;
      _mensajeProceso  = '';
      _error           = null;
      _productoNuevoId = null;
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.inventario,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text('Agregar producto')),
        body: BoundedContent(
          maxWidth: 980,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _buildEncabezado(),
              SizedBox(height: 20),
              if (_estado == _Estado.formulario) ...[
                _buildFormulario(),
                if (_error != null) ...[
                  SizedBox(height: 12),
                  _buildError(_error!),
                ],
              ] else if (_estado == _Estado.subiendo || _estado == _Estado.procesando)
                _buildProgreso()
              else if (_estado == _Estado.listo)
                _buildExito(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.add_box_outlined, color: AppColors.accent, size: 18),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Agregar producto nuevo',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              Text('Completa los datos del producto. La imagen es opcional.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, c) {
          final izquierda = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSeccionTitulo('Datos del producto', Icons.inventory_2_outlined),
              SizedBox(height: 8),
              _buildTarjetaDatos(),
            ],
          );
          final derecha = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSeccionTitulo('Imagen del producto', Icons.image_outlined),
              SizedBox(height: 8),
              _buildImagenReferencia(),
            ],
          );
          if (c.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [izquierda, SizedBox(height: 20), derecha],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: izquierda),
              SizedBox(width: 20),
              Expanded(child: derecha),
            ],
          );
        }),
        SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _registrar,
            icon: Icon(Icons.cloud_upload_outlined),
            label: Text('Registrar producto',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagenReferencia() {
    return GestureDetector(
      onTap: _seleccionarImagen,
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _imagenBytes != null
                ? AppColors.accent.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _imagenBytes != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_imagenBytes!, fit: BoxFit.contain),
                  Positioned(
                    bottom: 10, right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined, color: AppColors.accent, size: 13),
                          SizedBox(width: 5),
                          Text('Cambiar',
                              style: TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      color: AppColors.accent.withValues(alpha: 0.5), size: 36),
                  SizedBox(height: 8),
                  Text('Toca para agregar una imagen',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  SizedBox(height: 4),
                  Text('JPG, PNG, WEBP — opcional',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                ],
              ),
      ),
    );
  }

  Widget _buildTarjetaDatos() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _precioCtrl,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Precio (Bs.)',
                      prefixIcon: Icon(Icons.attach_money_rounded, size: 17),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Obligatorio';
                      final n = double.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Precio invalido';
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cantidadCtrl,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Cantidad inicial',
                      prefixIcon: Icon(Icons.numbers_rounded, size: 17),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Obligatorio';
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 0) return 'Cantidad invalida';
                      return null;
                    },
                  ),
                ),
              ],
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
      ),
    );
  }

  Widget _buildSeccionTitulo(String titulo, IconData icono) {
    return Row(
      children: [
        Icon(icono, color: AppColors.accent, size: 15),
        SizedBox(width: 7),
        Text(
          titulo.toUpperCase(),
          style: TextStyle(color: AppColors.textMuted, fontSize: 10.5,
              fontWeight: FontWeight.w700, letterSpacing: 0.9),
        ),
      ],
    );
  }

  Widget _buildProgreso() {
    final subiendo = _estado == _Estado.subiendo;
    return _TarjetaEstado(
      icono: subiendo ? Icons.cloud_upload_outlined : Icons.psychology_outlined,
      color: AppColors.warning,
      titulo: 'Guardando el producto...',
      subtitulo: _mensajeProceso,
      extra: Padding(
        padding: EdgeInsets.only(top: 20),
        child: LinearProgressIndicator(backgroundColor: AppColors.border, color: AppColors.warning),
      ),
    );
  }

  Widget _buildExito() {
    return _TarjetaEstado(
      icono: Icons.check_circle_outline_rounded,
      color: AppColors.accent,
      titulo: 'Producto registrado!',
      subtitulo: _mensajeProceso,
      extra: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FilledButton.icon(
          onPressed: _reiniciar,
          icon: Icon(Icons.add_rounded),
          label: Text('Agregar otro producto'),
          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ),
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
}

enum _Estado { formulario, subiendo, procesando, listo }

class _TarjetaEstado extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String subtitulo;
  final Widget? extra;

  const _TarjetaEstado({
    required this.icono, required this.color,
    required this.titulo, required this.subtitulo, this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icono, color: color, size: 52),
          SizedBox(height: 16),
          Text(titulo, textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text(subtitulo, textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          if (extra != null) extra!,
        ],
      ),
    );
  }
}