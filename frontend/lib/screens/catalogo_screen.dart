import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/categoria.dart';
import '../models/producto.dart';
import '../models/session.dart';
import '../screens/editar_producto_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

/// HU-26 - Tarea 1450: descuento vigente HOY de un producto
/// (viene de GET /promociones/ofertas).
class _Oferta {
  final double precioOferta;
  final double porcentaje;
  final DateTime fechaFin;
  final String promocion;

  _Oferta({
    required this.precioOferta,
    required this.porcentaje,
    required this.fechaFin,
    required this.promocion,
  });

  factory _Oferta.fromJson(Map<String, dynamic> j) => _Oferta(
        precioOferta: (j['precio_oferta'] as num).toDouble(),
        porcentaje: (j['porcentaje'] as num).toDouble(),
        fechaFin: DateTime.parse(j['fecha_fin'].toString()),
        promocion: (j['promocion_nombre'] ?? '') as String,
      );
}

class CatalogoScreen extends StatefulWidget {
  final String apiBase;

  CatalogoScreen({super.key, required this.apiBase});

  @override
  State<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends State<CatalogoScreen> {
  final _nombreCtrl    = TextEditingController();
  final _precioMinCtrl = TextEditingController();
  final _precioMaxCtrl = TextEditingController();

  List<Categoria>            _categorias     = [];
  int?                       _categoriaFiltro;
  List<Producto>             _productos      = [];
  bool                       _cargando       = true;
  String?                    _error;
  bool                       _filtrosActivos = false;
  final Map<int, Uint8List?> _imagenesCache  = {};

  // HU-26 1450: ofertas vigentes por id de producto
  Map<int, _Oferta>          _ofertas        = {};

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    _buscar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioMinCtrl.dispose();
    _precioMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarCategorias() async {
    try {
      final resp = await http.get(Uri.parse('${widget.apiBase}/categorias'));
      if (resp.statusCode != 200) return;
      final lista = jsonDecode(resp.body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _categorias = lista
            .map((e) => Categoria.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {}
  }

  /// HU-26 1450: ofertas de hoy. Si fallan, el catalogo se muestra sin ellas.
  Future<Map<int, _Oferta>> _cargarOfertas() async {
    try {
      final resp =
          await http.get(Uri.parse('${widget.apiBase}/promociones/ofertas'));
      if (resp.statusCode != 200) return {};
      final lista = jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;
      return {
        for (final e in lista.cast<Map<String, dynamic>>())
          (e['producto_id'] as num).toInt(): _Oferta.fromJson(e),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _buscar() async {
    setState(() { _cargando = true; _error = null; });

    final params = <String, String>{};
    if (_nombreCtrl.text.trim().isNotEmpty)    params['nombre']       = _nombreCtrl.text.trim();
    if (_precioMinCtrl.text.trim().isNotEmpty) params['precio_min']   = _precioMinCtrl.text.trim();
    if (_precioMaxCtrl.text.trim().isNotEmpty) params['precio_max']   = _precioMaxCtrl.text.trim();
    if (_categoriaFiltro != null)              params['categoria_id'] = _categoriaFiltro.toString();

    setState(() => _filtrosActivos = params.isNotEmpty);

    final uri = Uri.parse('${widget.apiBase}/productos').replace(queryParameters: params);
    try {
      // Productos y ofertas a la vez (HU-26 1450)
      final respuestas = await Future.wait([http.get(uri), _cargarOfertas()]);
      final resp    = respuestas[0] as http.Response;
      final ofertas = respuestas[1] as Map<int, _Oferta>;
      if (resp.statusCode != 200) throw Exception('Backend: ${resp.statusCode}');
      final lista    = jsonDecode(resp.body) as List<dynamic>;
      final productos = lista.map((e) => Producto.fromJson(e as Map<String, dynamic>)).toList();
      if (!mounted) return;
      setState(() { _productos = productos; _ofertas = ofertas; _cargando = false; });
      _cargarImagenes(productos);
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo cargar el catalogo: $e'; });
    }
  }

  Future<void> _cargarImagenes(List<Producto> productos) async {
    for (final p in productos) {
      if (_imagenesCache.containsKey(p.id)) continue;
      try {
        final resp = await http.get(
            Uri.parse('${widget.apiBase}/productos/${p.id}/imagen'));
        if (!mounted) return;
        setState(() =>
            _imagenesCache[p.id] =
                resp.statusCode == 200 ? resp.bodyBytes : null);
      } catch (_) {
        _imagenesCache[p.id] = null;
      }
    }
  }

  void _limpiarFiltros() {
    _nombreCtrl.clear();
    _precioMinCtrl.clear();
    _precioMaxCtrl.clear();
    setState(() => _categoriaFiltro = null);
    _buscar();
  }

  Future<void> _eliminarProducto(Producto p) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text('Eliminar producto',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        content: Text(
          'Seguro que quieres eliminar "${p.nombre}"?\nNo aparecera mas en el catalogo.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      final resp = await http.delete(
          Uri.parse('${widget.apiBase}/productos/${p.id}'));
      if (resp.statusCode != 204) throw Exception('Error ${resp.statusCode}');
      await _buscar();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Producto eliminado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  Future<void> _irAEditar(Producto p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditarProductoScreen(apiBase: widget.apiBase, producto: p),
      ),
    );
    _buscar();
  }

  Color _colorCategoria(int? id) {
    if (id == null) return AppColors.textMuted;
    for (final c in _categorias) {
      if (c.id == id)
        return AppColors.hexToColor(c.color) ?? AppColors.tagColorFor(id);
    }
    return AppColors.tagColorFor(id);
  }

  String? _nombreCategoria(int? id) {
    if (id == null) return null;
    for (final c in _categorias) {
      if (c.id == id) return c.nombre;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.catalogo,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text('Catalogo')),
        body: BoundedContent(
          maxWidth: 780,
          child: _cargando && _productos.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildEncabezado(),
                    SizedBox(height: 16),
                    _buildStats(),
                    SizedBox(height: 16),
                    _buildFiltros(),
                    SizedBox(height: 16),
                    _buildLista(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildEncabezado() {
    final esAdmin = Session.esAdmin;
    final enOferta = _productos.where((p) => _ofertas.containsKey(p.id)).length;
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.inventory_2_outlined,
              color: AppColors.accent, size: 18),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Catalogo de productos',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              Text(
                esAdmin
                    ? 'Toca el lapiz para editar nombre, precio o categoria.'
                    : 'Consulta los productos disponibles.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        // HU-26 1450: cuantos productos tienen promocion hoy
        if (enOferta > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_offer_outlined, size: 14, color: AppColors.danger),
                SizedBox(width: 5),
                Text('$enOferta en oferta',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStats() {
    final precios  = _productos.map((p) => p.precio).toList();
    final promedio = precios.isEmpty
        ? 0.0
        : precios.reduce((a, b) => a + b) / precios.length;
    final masAlto =
        precios.isEmpty ? 0.0 : precios.reduce((a, b) => a > b ? a : b);
    final cats =
        _productos.map((p) => p.categoriaId).whereType<int>().toSet().length;

    final tarjetas = [
      ('Productos',       '${_productos.length}'),
      ('Precio promedio', 'Bs. ${promedio.toStringAsFixed(2)}'),
      ('Precio maximo',   'Bs. ${masAlto.toStringAsFixed(2)}'),
      ('Categorias',      '$cats'),
    ];

    return LayoutBuilder(builder: (_, c) {
      final ancho = (c.maxWidth - 24) / (c.maxWidth > 500 ? 4 : 2);
      return Wrap(
        spacing: 8, runSpacing: 8,
        children: tarjetas.map((t) => SizedBox(
          width: ancho,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.$1,
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
                SizedBox(height: 8),
                Text(t.$2,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        )).toList(),
      );
    });
  }

  Widget _buildFiltros() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Buscar en el catalogo',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 10),
          TextField(
            controller: _nombreCtrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Nombre del producto',
              prefixIcon: Icon(Icons.search, size: 17),
              suffixIcon: _nombreCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 15),
                      onPressed: () { _nombreCtrl.clear(); _buscar(); },
                    ),
            ),
            onSubmitted: (_) => _buscar(),
          ),
          SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _precioMinCtrl,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'Precio min. (Bs.)'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _precioMaxCtrl,
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: 'Precio max. (Bs.)'),
              ),
            ),
          ]),
          SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            value: _categoriaFiltro,
            isDense: true,
            dropdownColor: AppColors.surfaceAlt,
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(labelText: 'Categoria'),
            items: [
              DropdownMenuItem(
                  value: null, child: Text('Todas las categorias')),
              ..._categorias.map(
                  (c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))),
            ],
            onChanged: (v) => setState(() => _categoriaFiltro = v),
          ),
          SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _buscar,
                icon: Icon(Icons.search, size: 15),
                label: Text('Buscar'),
              ),
            ),
            if (_filtrosActivos) ...[
              SizedBox(width: 8),
              TextButton.icon(
                onPressed: _limpiarFiltros,
                icon: Icon(Icons.filter_alt_off_outlined, size: 15),
                label: Text('Limpiar'),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _buildLista() {
    final esAdmin = Session.esAdmin;

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    if (_productos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  color: AppColors.textMuted, size: 32),
              SizedBox(height: 12),
              Text('Ningun producto coincide',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              SizedBox(height: 4),
              Text('Prueba con otro nombre o ajusta el rango de precio.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _productos.map((p) {
        final color          = _colorCategoria(p.categoriaId);
        final nombreCategoria = p.categoriaNombre ?? _nombreCategoria(p.categoriaId);
        final oferta         = _ofertas[p.id]; // HU-26 1450

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              // Solo el admin puede navegar a editar
              onTap: esAdmin ? () => _irAEditar(p) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: oferta != null
                          ? AppColors.danger.withValues(alpha: 0.45)
                          : AppColors.border),
                ),
                child: Row(
                  children: [
                    // Imagen o icono
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _imagenesCache[p.id] != null
                          ? Image.memory(_imagenesCache[p.id]!,
                              fit: BoxFit.cover)
                          : Icon(Icons.fastfood_outlined,
                              color: color, size: 19),
                    ),
                    SizedBox(width: 14),

                    // Nombre + categoria (+ promocion)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.nombre,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                          SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  nombreCategoria ?? 'Sin categoria',
                                  style: TextStyle(
                                      color: color,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (oferta != null) _chipPromocion(oferta),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Precio (HU-26 1450: con oferta, normal tachado + oferta)
                    _precio(p, oferta),

                    // Botones editar y eliminar — solo Admin
                    if (esAdmin) ...[
                      SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _irAEditar(p),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3)),
                          ),
                          child: Icon(Icons.edit_outlined,
                              color: AppColors.accent, size: 16),
                        ),
                      ),
                      SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _eliminarProducto(p),
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.danger.withValues(alpha: 0.3)),
                          ),
                          child: Icon(Icons.delete_outline_rounded,
                              color: AppColors.danger, size: 16),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── HU-26 1450: promocion en el catalogo del cajero / admin ──
  Widget _precio(Producto p, _Oferta? oferta) {
    if (oferta == null) {
      return Text(
        'Bs. ${p.precio.toStringAsFixed(2)}',
        style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w700,
            fontSize: 15),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Bs. ${p.precio.toStringAsFixed(2)}',
          style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.textMuted),
        ),
        Text(
          'Bs. ${oferta.precioOferta.toStringAsFixed(2)}',
          style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w800,
              fontSize: 15),
        ),
      ],
    );
  }

  Widget _chipPromocion(_Oferta oferta) {
    String dd(int x) => x.toString().padLeft(2, '0');
    final pct = oferta.porcentaje == oferta.porcentaje.roundToDouble()
        ? oferta.porcentaje.toStringAsFixed(0)
        : oferta.porcentaje.toStringAsFixed(1);
    return Tooltip(
      message: '${oferta.promocion} · hasta el '
          '${dd(oferta.fechaFin.day)}/${dd(oferta.fechaFin.month)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined, size: 11, color: AppColors.onDanger),
            SizedBox(width: 4),
            Text(
              '-$pct%  hasta ${dd(oferta.fechaFin.day)}/${dd(oferta.fechaFin.month)}',
              style: TextStyle(
                  color: AppColors.onDanger,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}