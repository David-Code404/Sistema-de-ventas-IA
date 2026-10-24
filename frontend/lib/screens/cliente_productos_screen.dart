import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/categoria.dart';
import '../theme/app_colors.dart';
import '../widgets/bounded_content.dart';

/// Umbral para avisar al cliente que quedan pocas unidades.
const _stockPocas = 5;

class _ProductoCliente {
  final int id;
  final String nombre;
  final int? categoriaId;
  final String? categoria;
  final double precio;
  final int stock;

  _ProductoCliente({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    required this.categoria,
    required this.precio,
    required this.stock,
  });

  factory _ProductoCliente.fromJson(Map<String, dynamic> j) => _ProductoCliente(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        categoriaId: j['categoria_id'] as int?,
        categoria: j['categoria_nombre'] as String?,
        precio: double.parse(j['precio'].toString()),
        stock: (j['stock'] as num).toInt(),
      );
}

/// Vista de solo lectura para el rol Cliente:
/// lista de productos con precio, categoria y existencias.
/// No incluye ninguna accion de edicion, alta o baja.
class ClienteProductosScreen extends StatefulWidget {
  final String apiBase;

  ClienteProductosScreen({super.key, required this.apiBase});

  @override
  State<ClienteProductosScreen> createState() => _ClienteProductosScreenState();
}

class _ClienteProductosScreenState extends State<ClienteProductosScreen> {
  List<_ProductoCliente> _items = [];
  List<Categoria> _categorias = [];
  bool _cargando = true;
  String? _error;
  final Map<int, Uint8List?> _imagenesCache = {};

  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  int? _categoriaFiltro;
  bool _soloDisponibles = false;

  @override
  void initState() {
    super.initState();
    _cargarCategorias();
    _cargar();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ── Datos ───────────────────────────────────────────────────
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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http.get(Uri.parse('${widget.apiBase}/inventario'));
      if (resp.statusCode != 200) throw Exception('Backend: ${resp.statusCode}');
      final lista = jsonDecode(resp.body) as List<dynamic>;
      final items = lista
          .map((e) => _ProductoCliente.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _cargando = false;
      });
      _cargarImagenes(items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los productos: $e';
      });
    }
  }

  Future<void> _cargarImagenes(List<_ProductoCliente> items) async {
    for (final p in items) {
      if (_imagenesCache.containsKey(p.id)) continue;
      try {
        final resp = await http
            .get(Uri.parse('${widget.apiBase}/productos/${p.id}/imagen'));
        if (!mounted) return;
        setState(() =>
            _imagenesCache[p.id] = resp.statusCode == 200 ? resp.bodyBytes : null);
      } catch (_) {
        _imagenesCache[p.id] = null;
      }
    }
  }

  // ── Filtros ─────────────────────────────────────────────────
  List<_ProductoCliente> get _visibles {
    final q = _busqueda.trim().toLowerCase();
    return _items.where((p) {
      if (_soloDisponibles && p.stock <= 0) return false;
      if (_categoriaFiltro != null && p.categoriaId != _categoriaFiltro) {
        return false;
      }
      if (q.isEmpty) return true;
      return p.nombre.toLowerCase().contains(q) ||
          (p.categoria ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Color _colorCategoria(int? id) {
    if (id == null) return AppColors.textMuted;
    for (final c in _categorias) {
      if (c.id == id) {
        return AppColors.hexToColor(c.color) ?? AppColors.tagColorFor(id);
      }
    }
    return AppColors.tagColorFor(id);
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return BoundedContent(
      maxWidth: 1100,
      child: _cargando && _items.isEmpty
          ? Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildEncabezado(),
                  SizedBox(height: 14),
                  _buildBuscador(),
                  SizedBox(height: 10),
                  _buildCategorias(),
                  SizedBox(height: 12),
                  _buildLista(),
                ],
              ),
            ),
    );
  }

  Widget _buildEncabezado() {
    final disponibles = _items.where((p) => p.stock > 0).length;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: AppColors.surface, borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.storefront_outlined,
              color: AppColors.accent, size: 18),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Productos',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              Text(
                _items.isEmpty
                    ? 'Consulta la disponibilidad de cada producto.'
                    : '$disponibles de ${_items.length} productos disponibles',
                style:
                    TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: _cargando ? null : _cargar,
          icon: Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildBuscador() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _busquedaCtrl,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar por producto o categoría',
              prefixIcon: Icon(Icons.search, size: 17),
              suffixIcon: _busqueda.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 15),
                      onPressed: () {
                        _busquedaCtrl.clear();
                        setState(() => _busqueda = '');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(width: 10),
        FilterChip(
          selected: _soloDisponibles,
          onSelected: (v) => setState(() => _soloDisponibles = v),
          label: Text('Solo disponibles'),
          showCheckmark: false,
          selectedColor: AppColors.accent.withValues(alpha: 0.16),
          side: BorderSide(
              color: _soloDisponibles
                  ? AppColors.accent.withValues(alpha: 0.6)
                  : AppColors.border),
        ),
      ],
    );
  }

  Widget _buildCategorias() {
    if (_categorias.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('Todas'),
              selected: _categoriaFiltro == null,
              showCheckmark: false,
              onSelected: (_) => setState(() => _categoriaFiltro = null),
            ),
          ),
          ..._categorias.map((c) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c.nombre),
                  selected: _categoriaFiltro == c.id,
                  showCheckmark: false,
                  onSelected: (_) => setState(() =>
                      _categoriaFiltro = _categoriaFiltro == c.id ? null : c.id),
                ),
              )),
        ],
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

    final visibles = _visibles;
    if (visibles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  color: AppColors.textMuted, size: 32),
              SizedBox(height: 12),
              Text(
                _items.isEmpty
                    ? 'Aún no hay productos registrados.'
                    : 'Ningún producto coincide con tu búsqueda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (_, c) {
      final espacio = 16.0;
      final columnas = c.maxWidth >= 900
          ? 4
          : c.maxWidth >= 640
              ? 3
              : 2;
      final ancho = (c.maxWidth - (columnas - 1) * espacio) / columnas;
      return Wrap(
        spacing: espacio,
        runSpacing: espacio,
        children: visibles
            .map((p) => SizedBox(width: ancho, child: _tarjeta(p)))
            .toList(),
      );
    });
  }

  Widget _tarjeta(_ProductoCliente p) {
    final color = _colorCategoria(p.categoriaId);
    final agotado = p.stock <= 0;

    return Opacity(
      opacity: agotado ? 0.7 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen grande, cuadrada, con la existencia encima
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: color.withValues(alpha: 0.14),
                    child: _imagenesCache[p.id] != null
                        ? Image.memory(_imagenesCache[p.id]!,
                            fit: BoxFit.cover)
                        : Icon(Icons.fastfood_outlined, color: color, size: 40),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _badgeStock(p.stock),
                  ),
                ],
              ),
            ),
            // Nombre y precio
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13.5,
                          height: 1.25)),
                  SizedBox(height: 6),
                  Text('Bs ${_formatoPrecio(p.precio)}',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 20)),
                  SizedBox(height: 6),
                  Text(p.categoria ?? 'Sin categoría',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 85.0 -> "85", 12.5 -> "12.50"
  String _formatoPrecio(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _badgeStock(int stock) {
    final String texto;
    final Color color;
    final IconData icono;

    if (stock <= 0) {
      texto = 'Agotado';
      color = AppColors.danger;
      icono = Icons.remove_circle_outline_rounded;
    } else if (stock < _stockPocas) {
      texto = 'Quedan $stock';
      color = Colors.orange;
      icono = Icons.warning_amber_rounded;
    } else {
      texto = '$stock disponibles';
      color = AppColors.accent;
      icono = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            color.withValues(alpha: 0.18), AppColors.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 12, color: color),
          SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}