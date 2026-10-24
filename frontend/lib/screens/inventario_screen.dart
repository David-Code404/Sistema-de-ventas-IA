import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/categoria.dart';
import '../models/session.dart';
import '../screens/agregar_producto_screen.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

const _stockMaximo = 1000000;

class _ItemInventario {
  final int id;
  final String nombre;
  final int? categoriaId;
  final String? categoria;
  final double precio;
  final int stock;
  final int stockMinimo;

  _ItemInventario({
    required this.id,
    required this.nombre,
    required this.categoriaId,
    required this.categoria,
    required this.precio,
    required this.stock,
    this.stockMinimo = 5,
  });

  factory _ItemInventario.fromJson(Map<String, dynamic> j) => _ItemInventario(
        id: j['id'] as int,
        nombre: j['nombre'] as String,
        categoriaId: j['categoria_id'] as int?,
        categoria: j['categoria_nombre'] as String?,
        precio: double.parse(j['precio'].toString()),
        stock: (j['stock'] as num).toInt(),
        stockMinimo: (j['stock_minimo'] as num?)?.toInt() ?? 5,
      );

  _ItemInventario conStock(int nuevo) => _ItemInventario(
        id: id,
        nombre: nombre,
        categoriaId: categoriaId,
        categoria: categoria,
        precio: precio,
        stock: nuevo,
        stockMinimo: stockMinimo,
      );

  bool get esStockBajo => stock < stockMinimo;
}

class _CambiosProducto {
  final String nombre;
  final double precio;
  final int categoriaId;
  final int stock;
  final int stockMinimo;

  const _CambiosProducto(
      this.nombre, this.precio, this.categoriaId, this.stock, this.stockMinimo);
}

class InventarioScreen extends StatefulWidget {
  final String apiBase;

  InventarioScreen({super.key, required this.apiBase});

  @override
  State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  static const _json = {'Content-Type': 'application/json'};

  List<_ItemInventario> _items = [];
  List<Categoria> _categorias = [];
  bool _cargando = true;
  String? _error;
  final Map<int, Uint8List?> _imagenesCache = {};
  final Set<int> _ocupados = {};

  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  bool _soloBajos = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCategorias();
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

  Future<void> _cargarImagenes(List<_ItemInventario> items) async {
    for (final p in items) {
      if (_imagenesCache.containsKey(p.id)) continue;
      try {
        final resp = await http
            .get(Uri.parse('${widget.apiBase}/productos/${p.id}/imagen'));
        if (!mounted) return;
        setState(() => _imagenesCache[p.id] =
            resp.statusCode == 200 ? resp.bodyBytes : null);
      } catch (_) {
        _imagenesCache[p.id] = null;
      }
    }
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
      if (!mounted) return;
      setState(() {
        _items = lista
            .map((e) => _ItemInventario.fromJson(e as Map<String, dynamic>))
            .toList();
        _cargando = false;
      });
      _cargarImagenes(_items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el inventario: $e';
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

  void _reemplazar(_ItemInventario nuevo) {
    final i = _items.indexWhere((e) => e.id == nuevo.id);
    if (i >= 0) setState(() => _items[i] = nuevo);
  }

  // ── Operaciones sobre la cantidad ───────────────────────────
  /// modo: 'sumar' | 'restar' | 'fijar'
  Future<bool> _cambiarStock(_ItemInventario item, String modo, int valor) async {
    if (_ocupados.contains(item.id)) return false;
    setState(() => _ocupados.add(item.id));
    try {
      final base = '${widget.apiBase}/inventario/${item.id}';
      final http.Response r;
      switch (modo) {
        case 'sumar':
          r = await http.post(Uri.parse('$base/aumentar'),
              headers: _json, body: jsonEncode({'cantidad': valor}));
        case 'restar':
          r = await http.post(Uri.parse('$base/disminuir'),
              headers: _json, body: jsonEncode({'cantidad': valor}));
        default:
          r = await http.put(Uri.parse(base),
              headers: _json, body: jsonEncode({'stock': valor}));
      }
      if (r.statusCode != 200) {
        _aviso(_detalle(r), error: true);
        return false;
      }
      final nuevo = ((jsonDecode(r.body) as Map<String, dynamic>)['stock'] as num).toInt();
      _reemplazar(item.conStock(nuevo));
      return true;
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _ocupados.remove(item.id));
    }
  }

  Future<void> _ajustarCantidad(_ItemInventario item) async {
    final ajuste = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _DialogAjustarStock(nombre: item.nombre, stock: item.stock),
    );
    if (ajuste == null) return;
    final ok = await _cambiarStock(item, ajuste.$1, ajuste.$2);
    if (ok) {
      final texto = switch (ajuste.$1) {
        'sumar' => 'Se añadieron ${ajuste.$2} unidades a "${item.nombre}".',
        'restar' => 'Se quitaron ${ajuste.$2} unidades de "${item.nombre}".',
        _ => 'La cantidad de "${item.nombre}" quedó en ${ajuste.$2}.',
      };
      _aviso(texto);
    }
  }

  // ── Editar y eliminar ───────────────────────────────────────
  Future<void> _editar(_ItemInventario item) async {
    if (_categorias.isEmpty) await _cargarCategorias();
    if (!mounted) return;
    final cambios = await showDialog<_CambiosProducto>(
      context: context,
      builder: (_) => _DialogEditarProducto(item: item, categorias: _categorias),
    );
    if (cambios == null) return;

    try {
      final r = await http.put(
        Uri.parse('${widget.apiBase}/productos/${item.id}'),
        headers: _json,
        body: jsonEncode({
          'nombre':       cambios.nombre,
          'precio':       cambios.precio,
          'categoria_id': cambios.categoriaId,
          'stock_minimo': cambios.stockMinimo,
        }),
      );
      if (r.statusCode != 200) {
        _aviso(_detalle(r), error: true);
        return;
      }
      if (cambios.stock != item.stock) {
        final ok = await _cambiarStock(item, 'fijar', cambios.stock);
        if (!ok) return;
      }
      await _cargar();
      _aviso('Producto "${cambios.nombre}" actualizado.');
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  Future<void> _eliminar(_ItemInventario item) async {
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
          '¿Eliminar "${item.nombre}" del inventario?\n\n'
          'Dejará de aparecer en el catálogo y en el inventario. '
          'Las ventas anteriores que lo incluyen se conservan.',
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
      final r = await http.delete(
          Uri.parse('${widget.apiBase}/productos/${item.id}'));
      if (r.statusCode != 204) {
        _aviso(_detalle(r), error: true);
        return;
      }
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e.id == item.id));
      _aviso('Producto "${item.nombre}" eliminado.');
    } catch (e) {
      _aviso('No se pudo conectar con el servidor: $e', error: true);
    }
  }

  Future<void> _irAAgregar() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AgregarProductoScreen(apiBase: widget.apiBase)),
    );
    _cargar();
  }

  // ── Pantalla ────────────────────────────────────────────────
  List<_ItemInventario> get _visibles {
    final q = _busqueda.trim().toLowerCase();
    return _items.where((p) {
      if (_soloBajos && !p.esStockBajo) return false;
      if (q.isEmpty) return true;
      return p.nombre.toLowerCase().contains(q) ||
          (p.categoria ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.inventario,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text('Inventario')),
        body: BoundedContent(
          maxWidth: 900,
          child: _cargando && _items.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _buildEncabezado(),
                      SizedBox(height: 16),
                      _buildStats(),
                      if (_items.any((i) => i.esStockBajo)) ...[
                        SizedBox(height: 12),
                        _buildAlertaStockBajo(),
                      ],
                      SizedBox(height: 16),
                      _buildFiltros(),
                      SizedBox(height: 12),
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
      child: Icon(Icons.warehouse_outlined,
          color: AppColors.accent, size: 18),
    );
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Inventario',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        Text(
          Session.esAdmin
              ? 'Ajusta con − y +, o toca la cantidad para añadir, quitar o fijar un valor.'
              : 'Cantidad disponible de cada producto.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
    final boton = Session.esAdmin
        ? FilledButton.icon(
            onPressed: _irAAgregar,
            icon: Icon(Icons.add_rounded, size: 17),
            label: Text('Agregar producto'),
          )
        : null;

    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth >= 560) {
        return Row(
          children: [
            icono,
            SizedBox(width: 12),
            Expanded(child: titulo),
            if (boton != null) ...[SizedBox(width: 8), boton],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [icono, SizedBox(width: 12), Expanded(child: titulo)]),
          if (boton != null) ...[SizedBox(height: 10), boton],
        ],
      );
    });
  }

  Widget _buildStats() {
    final unidades = _items.fold<int>(0, (a, b) => a + b.stock);
    final bajos = _items.where((i) => i.esStockBajo).length;
    final valor = _items.fold<double>(0, (a, b) => a + b.stock * b.precio);

    final tarjetas = [
      ('Productos', '${_items.length}', AppColors.textPrimary),
      ('Unidades totales', '$unidades', AppColors.textPrimary),
      ('Valor del inventario', 'Bs. ${valor.toStringAsFixed(2)}', AppColors.textPrimary),
      ('Stock bajo', '$bajos', bajos > 0 ? AppColors.danger : AppColors.textPrimary),
    ];

    return LayoutBuilder(builder: (_, c) {
      final columnas = c.maxWidth > 560 ? 4 : 2;
      final ancho = (c.maxWidth - (columnas - 1) * 8) / columnas;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tarjetas
            .map((t) => SizedBox(
                  width: ancho,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4)),
                        SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(t.$2,
                              style: TextStyle(
                                  color: t.$3,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      );
    });
  }

  /// Resalta los productos con stock bajo su mínimo configurable.
  Widget _buildAlertaStockBajo() {
    final bajos = _items.where((i) => i.esStockBajo).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 17, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Productos bajo su stock mínimo',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: bajos
                .map((p) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        p.stock == 0
                            ? '${p.nombre} · Agotado (mín. ${p.stockMinimo})'
                            : '${p.nombre} · quedan ${p.stock} / mín. ${p.stockMinimo}',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    final bajos = _items.where((i) => i.esStockBajo).length;
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
          selected: _soloBajos,
          onSelected: (v) => setState(() => _soloBajos = v),
          avatar: Icon(Icons.warning_amber_rounded,
              size: 15,
              color: _soloBajos ? AppColors.danger : AppColors.textMuted),
          label: Text('Stock bajo ($bajos)'),
          showCheckmark: false,
          selectedColor: AppColors.danger.withValues(alpha: 0.16),
          side: BorderSide(
              color: _soloBajos
                  ? AppColors.danger.withValues(alpha: 0.6)
                  : AppColors.border),
        ),
      ],
    );
  }

  Widget _buildLista() {
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
    final visibles = _visibles;
    if (visibles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              _items.isEmpty
                  ? 'Aún no hay productos en el inventario.'
                  : 'Ningún producto coincide con la búsqueda.',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return Column(children: visibles.map(_fila).toList());
  }

  Widget _fila(_ItemInventario p) {
    final agotado = p.stock == 0;
    final bajo = p.esStockBajo;
    final colorStock = bajo ? AppColors.danger : AppColors.accent;
    final admin = Session.esAdmin;
    final ocupado = _ocupados.contains(p.id);

    final info = Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colorStock.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: _imagenesCache[p.id] != null
              ? Image.memory(_imagenesCache[p.id]!, fit: BoxFit.cover)
              : Icon(Icons.inventory_2_outlined, color: colorStock, size: 22),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
              SizedBox(height: 3),
              Text(p.categoria ?? 'Sin categoria',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Bs. ${p.precio.toStringAsFixed(2)}',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text('precio',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
          ],
        ),
      ],
    );

    final cantidad = _cantidadVisual(p, colorStock, agotado, bajo);

    final controles = admin
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _botonIcono(Icons.remove_rounded, AppColors.danger,
                  'Quitar 1', (ocupado || agotado) ? null : () => _cambiarStock(p, 'restar', 1)),
              Tooltip(
                message: 'Toca para añadir, quitar o fijar la cantidad',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: ocupado ? null : () => _ajustarCantidad(p),
                  child: SizedBox(width: 78, child: cantidad),
                ),
              ),
              _botonIcono(Icons.add_rounded, AppColors.accent, 'Añadir 1',
                  ocupado ? null : () => _cambiarStock(p, 'sumar', 1)),
              SizedBox(width: 12),
              _botonIcono(Icons.edit_outlined, AppColors.textSecondary,
                  'Editar producto', ocupado ? null : () => _editar(p)),
              SizedBox(width: 6),
              _botonIcono(Icons.delete_outline_rounded, AppColors.danger,
                  'Eliminar producto', ocupado ? null : () => _eliminar(p)),
            ],
          )
        : SizedBox(width: 78, child: cantidad);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bajo
              ? Color.alphaBlend(
                  AppColors.danger.withValues(alpha: 0.08), AppColors.surface)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: bajo
                  ? AppColors.danger.withValues(alpha: 0.5)
                  : AppColors.border),
        ),
        child: LayoutBuilder(builder: (_, c) {
          if (c.maxWidth >= 640) {
            return Row(
              children: [
                Expanded(child: info),
                SizedBox(width: 16),
                controles,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: controles),
            ],
          );
        }),
      ),
    );
  }

  Widget _cantidadVisual(_ItemInventario p, Color color, bool agotado, bool bajo) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${p.stock}',
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.w700)),
        Text(agotado ? 'Agotado' : (bajo ? 'Stock bajo' : 'unidades'),
            style: TextStyle(
                color: bajo ? AppColors.danger : AppColors.textMuted,
                fontSize: 10.5,
                fontWeight: bajo ? FontWeight.w700 : FontWeight.w500)),
      ],
    );
  }

  Widget _botonIcono(
      IconData icono, Color color, String ayuda, VoidCallback? onTap) {
    final activo = onTap != null;
    return Tooltip(
      message: ayuda,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: activo ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: activo ? 0.35 : 0.12)),
          ),
          child: Icon(icono,
              size: 18, color: color.withValues(alpha: activo ? 1 : 0.35)),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  Diálogos como StatefulWidget (controladores propios)
// ══════════════════════════════════════════════════════════════
class _DialogAjustarStock extends StatefulWidget {
  final String nombre;
  final int stock;

  const _DialogAjustarStock({required this.nombre, required this.stock});

  @override
  State<_DialogAjustarStock> createState() => _DialogAjustarStockState();
}

class _DialogAjustarStockState extends State<_DialogAjustarStock> {
  final _ctrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _modo = 'sumar';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _valor => int.tryParse(_ctrl.text.trim());

  int? get _resultado {
    final v = _valor;
    if (v == null) return null;
    return switch (_modo) {
      'sumar' => widget.stock + v,
      'restar' => widget.stock - v,
      _ => v,
    };
  }

  String? _validar(String? texto) {
    final n = int.tryParse((texto ?? '').trim());
    if (n == null) return 'Ingresa un número entero';
    if (n > _stockMaximo) return 'Máximo $_stockMaximo';
    if (_modo == 'fijar') return n < 0 ? 'No puede ser negativo' : null;
    if (n <= 0) return 'Ingresa un número mayor a 0';
    if (_modo == 'restar' && n > widget.stock) {
      return 'Solo hay ${widget.stock} unidades';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final etiqueta = switch (_modo) {
      'sumar' => 'Unidades a añadir',
      'restar' => 'Unidades a quitar',
      _ => 'Nueva cantidad total',
    };
    final resultado = _resultado;
    final confirmar = switch (_modo) {
      'sumar' => 'Añadir',
      'restar' => 'Quitar',
      _ => 'Fijar cantidad',
    };

    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text('Ajustar cantidad de "${widget.nombre}"',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cantidad actual: ${widget.stock} unidades',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
              SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'sumar',
                      label: Text('Añadir'),
                      icon: Icon(Icons.add_rounded, size: 16)),
                  ButtonSegment(
                      value: 'restar',
                      label: Text('Quitar'),
                      icon: Icon(Icons.remove_rounded, size: 16)),
                  ButtonSegment(
                      value: 'fijar',
                      label: Text('Fijar'),
                      icon: Icon(Icons.edit_outlined, size: 16)),
                ],
                selected: {_modo},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _modo = s.first),
              ),
              SizedBox(height: 14),
              TextFormField(
                controller: _ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: etiqueta,
                  prefixIcon: Icon(Icons.numbers_rounded, size: 17),
                ),
                validator: _validar,
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 10),
              Text(
                resultado == null
                    ? ' '
                    : (resultado < 0
                        ? 'No hay suficiente stock'
                        : 'Quedará en $resultado unidades'),
                style: TextStyle(
                    color: (resultado ?? 0) < 0
                        ? AppColors.danger
                        : AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ],
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
            Navigator.pop(context, (_modo, int.parse(_ctrl.text.trim())));
          },
          child: Text(confirmar),
        ),
      ],
    );
  }
}

class _DialogEditarProducto extends StatefulWidget {
  final _ItemInventario item;
  final List<Categoria> categorias;

  const _DialogEditarProducto({required this.item, required this.categorias});

  @override
  State<_DialogEditarProducto> createState() => _DialogEditarProductoState();
}

class _DialogEditarProductoState extends State<_DialogEditarProducto> {
  late final TextEditingController _nombre =
      TextEditingController(text: widget.item.nombre);
  late final TextEditingController _precio =
      TextEditingController(text: widget.item.precio.toStringAsFixed(2));
  late final TextEditingController _stock =
      TextEditingController(text: '${widget.item.stock}');
  late final TextEditingController _stockMinimo =
      TextEditingController(text: '${widget.item.stockMinimo}');
  final _formKey = GlobalKey<FormState>();
  late int? _categoriaId = widget.categorias.any((c) => c.id == widget.item.categoriaId)
      ? widget.item.categoriaId
      : null;

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    _stock.dispose();
    _stockMinimo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: Text('Editar producto',
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
                  controller: _nombre,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Nombre del producto',
                    prefixIcon: Icon(Icons.label_outline, size: 17),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'El nombre es obligatorio';
                    if (t.length > 150) return 'Máximo 150 caracteres';
                    return null;
                  },
                ),
                SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _precio,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Precio (Bs.)',
                          prefixIcon: Icon(Icons.attach_money_rounded, size: 17),
                        ),
                        validator: (v) {
                          final n =
                              double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Precio inválido';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          prefixIcon: Icon(Icons.numbers_rounded, size: 17),
                        ),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n < 0) return 'Cantidad inválida';
                          if (n > _stockMaximo) return 'Máximo $_stockMaximo';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _stockMinimo,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Stock mínimo',
                    hintText: 'Ej. 5',
                    prefixIcon: Icon(Icons.warning_amber_rounded, size: 17),
                    helperText: 'Alerta cuando el stock baje de este valor',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 0) return 'Debe ser 0 o mayor';
                    if (n > _stockMaximo) return 'Máximo $_stockMaximo';
                    return null;
                  },
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _categoriaId,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Categoría',
                    prefixIcon: Icon(Icons.category_outlined, size: 17),
                  ),
                  items: widget.categorias
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoriaId = v),
                  validator: (v) => v == null ? 'Selecciona una categoría' : null,
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
            Navigator.pop(
              context,
              _CambiosProducto(
                _nombre.text.trim(),
                double.parse(_precio.text.trim().replaceAll(',', '.')),
                _categoriaId!,
                int.parse(_stock.text.trim()),
                int.parse(_stockMinimo.text.trim()),
              ),
            );
          },
          child: Text('Guardar cambios'),
        ),
      ],
    );
  }
}