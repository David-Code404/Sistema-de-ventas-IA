import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/categoria.dart';
import '../models/producto.dart';
import '../models/promocion.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';

/// HU-26 - Tarea 1430: panel para crear, editar, activar y desactivar
/// promociones. Solo para el Administrador.
class PromocionesScreen extends StatefulWidget {
  final String apiBase;

  PromocionesScreen({super.key, this.apiBase = AppConfig.apiBase});

  @override
  State<PromocionesScreen> createState() => _PromocionesScreenState();
}

/// Filtros de la lista: (valor de 'estado' del backend, etiqueta). null = todas.
const _filtros = <(String?, String)>[
  (null, 'Todas'),
  ('vigente', 'Vigentes'),
  ('programada', 'Programadas'),
  ('vencida', 'Vencidas'),
  ('inactiva', 'Inactivas'),
];

String _dd(int x) => x.toString().padLeft(2, '0');
String _fecha(DateTime d) => '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
String _bs(double v) => 'Bs. ${v.toStringAsFixed(2)}';
String _pct(double v) =>
    v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(2)}%';

class _PromocionesScreenState extends State<PromocionesScreen> {
  // ── Datos ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _promos = [];
  List<Producto> _productos = [];
  List<Categoria> _categorias = [];
  bool _cargando = true;
  String? _error;
  String? _filtro;
  final Set<int> _cambiandoEstado = {};

  // ── Formulario ──────────────────────────────────────────────
  bool _formularioAbierto = false;
  int? _editandoId;
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _porcentajeCtrl = TextEditingController();
  TipoPromocion _tipo = TipoPromocion.producto;
  int? _productoId;
  int? _categoriaId;
  DateTime? _inicio;
  DateTime? _fin;
  bool _activa = true;
  bool _guardando = false;
  String? _errorFormulario;

  String get _qs => 'usuario_id=${Session.usuarioId ?? 0}';

  @override
  void initState() {
    super.initState();
    if (Session.esAdmin) _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _porcentajeCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  //  Comunicacion con el backend
  // ══════════════════════════════════════════════════════════
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        http.get(Uri.parse('${widget.apiBase}/promociones?$_qs')),
        http.get(Uri.parse('${widget.apiBase}/productos')),
        http.get(Uri.parse('${widget.apiBase}/categorias')),
      ]);
      for (final resp in r) {
        if (resp.statusCode != 200) throw Exception(_mensajeDeError(resp));
      }
      List<dynamic> lista(http.Response resp) =>
          jsonDecode(utf8.decode(resp.bodyBytes)) as List<dynamic>;

      if (!mounted) return;
      setState(() {
        _promos = lista(r[0]).cast<Map<String, dynamic>>();
        _productos = lista(r[1])
            .map((e) => Producto.fromJson(e as Map<String, dynamic>))
            .toList();
        _categorias = lista(r[2])
            .map((e) => Categoria.fromJson(e as Map<String, dynamic>))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  String _mensajeDeError(http.Response respuesta) {
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = (cuerpo as Map)['detail'];
      if (detalle is String) return detalle;
      if (detalle is List && detalle.isNotEmpty) {
        final primero = detalle.first;
        if (primero is Map && primero['msg'] != null) {
          return primero['msg'].toString();
        }
      }
    } catch (_) {}
    return 'Ocurrio un error inesperado (${respuesta.statusCode}).';
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_inicio == null || _fin == null) {
      setState(() => _errorFormulario = 'Elige la fecha de inicio y la de fin.');
      return;
    }
    final promo = Promocion(
      nombre: _nombreCtrl.text,
      tipo: _tipo,
      productoId: _productoId,
      categoriaId: _categoriaId,
      porcentaje: double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.')) ?? 0,
      fechaInicio: _inicio!,
      fechaFin: _fin!,
      activa: _activa,
    );
    final problema = promo.validar();
    if (problema != null) {
      setState(() => _errorFormulario = problema);
      return;
    }

    setState(() {
      _guardando = true;
      _errorFormulario = null;
    });
    try {
      final cuerpo = jsonEncode(promo.toJson());
      final headers = {'Content-Type': 'application/json'};
      final resp = _editandoId == null
          ? await http.post(Uri.parse('${widget.apiBase}/promociones?$_qs'),
              headers: headers, body: cuerpo)
          : await http.put(
              Uri.parse('${widget.apiBase}/promociones/$_editandoId?$_qs'),
              headers: headers,
              body: cuerpo);
      if (!mounted) return;
      if (resp.statusCode >= 400) {
        setState(() {
          _guardando = false;
          _errorFormulario = _mensajeDeError(resp);
        });
        return;
      }
      final creada = _editandoId == null;
      setState(() {
        _guardando = false;
        _formularioAbierto = false;
      });
      _aviso(creada ? 'Promocion creada.' : 'Promocion actualizada.');
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorFormulario = 'No se pudo conectar con el servidor: $e';
      });
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> p, bool activa) async {
    final id = p['id'] as int;
    setState(() => _cambiandoEstado.add(id));
    try {
      final resp = await http.patch(
        Uri.parse('${widget.apiBase}/promociones/$id/estado?$_qs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'activa': activa}),
      );
      if (!mounted) return;
      if (resp.statusCode >= 400) {
        _aviso(_mensajeDeError(resp), error: true);
      } else {
        _aviso(activa ? 'Promocion activada.' : 'Promocion desactivada.');
        await _cargar();
      }
    } catch (e) {
      if (mounted) _aviso('No se pudo conectar con el servidor.', error: true);
    } finally {
      if (mounted) setState(() => _cambiandoEstado.remove(id));
    }
  }

  void _aviso(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  // ══════════════════════════════════════════════════════════
  //  Formulario: abrir / cerrar
  // ══════════════════════════════════════════════════════════
  void _abrirCrear() {
    final hoy = DateTime.now();
    setState(() {
      _editandoId = null;
      _nombreCtrl.clear();
      _porcentajeCtrl.clear();
      _tipo = TipoPromocion.producto;
      _productoId = null;
      _categoriaId = null;
      _inicio = DateTime(hoy.year, hoy.month, hoy.day);
      _fin = null;
      _activa = true;
      _errorFormulario = null;
      _formularioAbierto = true;
    });
  }

  void _abrirEditar(Map<String, dynamic> json) {
    final p = Promocion.fromJson(json);
    setState(() {
      _editandoId = p.id;
      _nombreCtrl.text = p.nombre;
      _porcentajeCtrl.text = _pct(p.porcentaje).replaceAll('%', '');
      _tipo = p.tipo;
      // Si el producto ya no esta en el catalogo, se obliga a elegir otro
      _productoId = _productos.any((x) => x.id == p.productoId) ? p.productoId : null;
      _categoriaId = p.categoriaId;
      _inicio = p.fechaInicio;
      _fin = p.fechaFin;
      _activa = p.activa;
      _errorFormulario = null;
      _formularioAbierto = true;
    });
  }

  void _cerrarFormulario() => setState(() {
        _formularioAbierto = false;
        _errorFormulario = null;
      });

  Future<void> _elegirFecha({required bool esInicio}) async {
    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
    final actual = esInicio ? _inicio : _fin;
    // Al editar, la fecha de inicio puede ser anterior a hoy
    final primera = esInicio
        ? (_inicio != null && _inicio!.isBefore(hoySolo) ? _inicio! : hoySolo)
        : (_inicio != null && _inicio!.isAfter(hoySolo) ? _inicio! : hoySolo);
    var inicial = actual ?? primera;
    if (inicial.isBefore(primera)) inicial = primera;

    final elegida = await showDatePicker(
      context: context,
      firstDate: primera,
      lastDate: DateTime(hoy.year + 2, 12, 31),
      initialDate: inicial,
      helpText: esInicio ? 'Fecha de inicio' : 'Fecha de fin',
    );
    if (elegida == null) return;
    setState(() {
      if (esInicio) {
        _inicio = elegida;
        if (_fin != null && _fin!.isBefore(elegida)) _fin = null;
      } else {
        _fin = elegida;
      }
    });
  }

  // ══════════════════════════════════════════════════════════
  //  Interfaz
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.promociones,
      apiBase: widget.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Promociones'),
          actions: [
            if (Session.esAdmin && !_formularioAbierto && _error == null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: _cargando ? null : _abrirCrear,
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Nueva promoción'),
                ),
              ),
          ],
        ),
        body: !Session.esAdmin
            ? Center(
                child: Text('Esta seccion es solo para administradores.',
                    style: TextStyle(color: AppColors.textSecondary)))
            : BoundedContent(maxWidth: 1100, child: _contenido()),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando && _promos.isEmpty && _productos.isEmpty) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 30),
              SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 12),
              TextButton.icon(
                onPressed: _cargar,
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final visibles = _filtro == null
        ? _promos
        : _promos.where((p) => p['estado'] == _filtro).toList();

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_formularioAbierto) ...[
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 720),
                child: _formulario(),
              ),
            ),
            SizedBox(height: 20),
          ],
          _barraFiltros(),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: AppColors.textMuted),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                    'Las promociones se desactivan solas cuando pasa su fecha de fin.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ),
            ],
          ),
          SizedBox(height: 12),
          if (visibles.isEmpty)
            _vacio()
          else
            LayoutBuilder(builder: (context, c) {
              final columnas = c.maxWidth > 900 ? 3 : (c.maxWidth > 580 ? 2 : 1);
              final ancho = (c.maxWidth - (columnas - 1) * 12) / columnas;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in visibles)
                    SizedBox(width: ancho, child: _tarjeta(p)),
                ],
              );
            }),
        ],
      ),
    );
  }

  // ── Filtros ─────────────────────────────────────────────────
  Widget _barraFiltros() {
    int cuantas(String? estado) => estado == null
        ? _promos.length
        : _promos.where((p) => p['estado'] == estado).length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final f in _filtros)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _filtro = f.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: _filtro == f.$1
                    ? AppColors.accent.withValues(alpha: 0.16)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _filtro == f.$1
                        ? AppColors.accent.withValues(alpha: 0.6)
                        : AppColors.border),
              ),
              child: Text('${f.$2}  ${cuantas(f.$1)}',
                  style: TextStyle(
                      color: _filtro == f.$1
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _vacio() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.local_offer_outlined, size: 30, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text(
            _promos.isEmpty
                ? 'Todavia no hay promociones. Usa "Nueva promoción" para crear la primera.'
                : 'No hay promociones en este filtro.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de una promocion ────────────────────────────────
  (Color, String) _colorEstado(String? estado) {
    switch (estado) {
      case 'vigente':
        return (AppColors.accent, 'Vigente');
      case 'programada':
        return (AppColors.info, 'Programada');
      case 'vencida':
        return (AppColors.warning, 'Vencida');
      default:
        return (AppColors.textMuted, 'Inactiva');
    }
  }

  Widget _tarjeta(Map<String, dynamic> json) {
    final p = Promocion.fromJson(json);
    final (color, etiqueta) = _colorEstado(json['estado'] as String?);
    final id = json['id'] as int;
    final ocupado = _cambiandoEstado.contains(id);
    final precio = (json['producto_precio'] as num?)?.toDouble();
    final vencida = json['estado'] == 'vencida';
    // HU-26 1460: cuando el sistema la desactivo por vencer (null si no)
    final autoEn = DateTime.tryParse('${json['desactivada_auto_en'] ?? ''}')?.toLocal();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: json['estado'] == 'vigente'
                ? AppColors.accent.withValues(alpha: 0.45)
                : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('-${_pct(p.porcentaje)}',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                            p.tipo == TipoPromocion.producto
                                ? Icons.inventory_2_outlined
                                : Icons.category_outlined,
                            size: 13,
                            color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                              p.tipo == TipoPromocion.producto
                                  ? p.destino
                                  : 'Categoría: ${p.destino}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _chip(etiqueta, color),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 14, color: AppColors.textMuted),
              SizedBox(width: 5),
              Text('${_fecha(p.fechaInicio)}  →  ${_fecha(p.fechaFin)}',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          // HU-26 1460: aviso cuando el sistema la desactivo por vencer
          if (autoEn != null) ...[
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.timer_off_outlined, size: 14, color: AppColors.warning),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                      'Desactivada automáticamente el ${_fecha(autoEn)} '
                      'al vencer su fecha de fin',
                      style: TextStyle(color: AppColors.warning, fontSize: 11.5)),
                ),
              ],
            ),
          ],
          if (precio != null) ...[
            SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 14, color: AppColors.textMuted),
                SizedBox(width: 5),
                Text(_bs(precio),
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough)),
                SizedBox(width: 6),
                Text(_bs(p.precioConDescuento(precio)),
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ocupado ? null : () => _abrirEditar(json),
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
              SizedBox(width: 10),
              Tooltip(
                message: vencida
                    ? 'Vencida: edita las fechas para volver a usarla'
                    : (p.activa ? 'Desactivar' : 'Activar'),
                child: ocupado
                    ? SizedBox(
                        width: 40,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.accent),
                          ),
                        ),
                      )
                    : Switch(
                        value: p.activa,
                        onChanged: vencida && !p.activa
                            ? null // HU-26 1460
                            : (v) => _cambiarEstado(json, v),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(texto,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }

  // ── Formulario de crear / editar ────────────────────────────
  Widget _formulario() {
    final editando = _editandoId != null;
    final producto = _tipo == TipoPromocion.producto && _productoId != null
        ? _productos.where((x) => x.id == _productoId).firstOrNull
        : null;
    final porcentaje =
        double.tryParse(_porcentajeCtrl.text.replaceAll(',', '.'));

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
            Text(editando ? 'Editar promoción' : 'Nueva promoción',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            SizedBox(height: 14),

            // Nombre
            TextFormField(
              controller: _nombreCtrl,
              autofocus: !editando,
              maxLength: 100,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Nombre de la promoción',
                hintText: 'Ej. Black Friday snacks',
                counterText: '',
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Minimo 3 caracteres'
                  : null,
            ),
            SizedBox(height: 14),

            // Tipo
            Text('Se aplica a',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            SizedBox(height: 6),
            SegmentedButton<TipoPromocion>(
              segments: [
                ButtonSegment(
                    value: TipoPromocion.producto,
                    icon: Icon(Icons.inventory_2_outlined, size: 16),
                    label: Text('Un producto')),
                ButtonSegment(
                    value: TipoPromocion.categoria,
                    icon: Icon(Icons.category_outlined, size: 16),
                    label: Text('Una categoría')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => setState(() => _tipo = s.first),
            ),
            SizedBox(height: 12),

            // Producto o categoria
            if (_tipo == TipoPromocion.producto)
              DropdownButtonFormField<int>(
                key: ValueKey('producto_$_editandoId'),
                value: _productoId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Producto'),
                items: [
                  for (final p in _productos)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.nombre}  ·  ${_bs(p.precio)}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _productoId = v),
                validator: (v) => v == null ? 'Elige un producto' : null,
              )
            else
              DropdownButtonFormField<int>(
                key: ValueKey('categoria_$_editandoId'),
                value: _categoriaId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Categoría'),
                items: [
                  for (final c in _categorias)
                    DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                ],
                onChanged: (v) => setState(() => _categoriaId = v),
                validator: (v) => v == null ? 'Elige una categoría' : null,
              ),
            SizedBox(height: 12),

            // Porcentaje
            TextFormField(
              controller: _porcentajeCtrl,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Descuento',
                hintText: 'Ej. 15',
                suffixText: '%',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                if (n == null) return 'Escribe un numero';
                if (n < Promocion.porcentajeMinimo ||
                    n > Promocion.porcentajeMaximo) {
                  return 'Debe ser mayor que 0 y menor que 100';
                }
                return null;
              },
            ),
            if (producto != null &&
                porcentaje != null &&
                porcentaje > 0 &&
                porcentaje < 100) ...[
              SizedBox(height: 6),
              Text(
                  '${producto.nombre}: ${_bs(producto.precio)} → '
                  '${_bs(((producto.precio * (100 - porcentaje) / 100) * 100).round() / 100)}',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
            SizedBox(height: 14),

            // Fechas
            Row(
              children: [
                Expanded(
                    child: _botonFecha('Desde', _inicio,
                        () => _elegirFecha(esInicio: true))),
                SizedBox(width: 10),
                Expanded(
                    child: _botonFecha(
                        'Hasta', _fin, () => _elegirFecha(esInicio: false))),
              ],
            ),
            SizedBox(height: 8),

            // Activa
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _activa,
              onChanged: (v) => setState(() => _activa = v),
              title: Text('Activa',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
              subtitle: Text(
                  'Si la desactivas, no se aplica aunque esté dentro de sus fechas.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ),

            if (_errorFormulario != null) ...[
              SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorFormulario!,
                        style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
                  ),
                ],
              ),
            ],
            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _guardando ? null : _cerrarFormulario,
                  child: Text('Cancelar'),
                ),
                SizedBox(width: 8),
                FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accentOnAccent))
                      : Text(editando ? 'Guardar cambios' : 'Crear promoción'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonFecha(String etiqueta, DateTime? valor, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: etiqueta,
          suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
        ),
        child: Text(valor == null ? 'Elegir' : _fecha(valor),
            style: TextStyle(
                color: valor == null ? AppColors.textMuted : AppColors.textPrimary,
                fontSize: 13.5)),
      ),
    );
  }
}