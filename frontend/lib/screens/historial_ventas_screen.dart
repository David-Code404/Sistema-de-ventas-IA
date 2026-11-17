import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/estado_venta.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';
import '../widgets/comprobante_vista.dart';
import '../widgets/descarga.dart';
import 'detalle_venta_screen.dart';

const List<String> _camposBusqueda = ['Codigo', 'Producto', 'Fecha'];

class HistorialVentasScreen extends StatefulWidget {
  HistorialVentasScreen({super.key});

  static const String apiBase = AppConfig.apiBase;

  @override
  State<HistorialVentasScreen> createState() => _HistorialVentasScreenState();
}

class _HistorialVentasScreenState extends State<HistorialVentasScreen> {
  List<Map<String, dynamic>> _ventas = [];
  bool    _cargando = true;
  String? _error;
  bool    _exportando = false;

  // Filtro de texto
  final _busquedaCtrl = TextEditingController();
  String _campoBusqueda = _camposBusqueda.first;
  String _busqueda      = '';

  // Filtro por rango de fechas
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  // Comprobante abierto en vista grande (dentro del area de contenido)
  Map<String, dynamic>? _comprobanteAmpliado;

  @override
  void initState() {
    super.initState();
    _cargarVentas();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  // ── Carga ─────────────────────────────────────────────────
  Future<void> _cargarVentas() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final resp = await http.get(
          Uri.parse('${HistorialVentasScreen.apiBase}/ventas'));
      if (resp.statusCode != 200) {
        throw Exception('El backend respondio ${resp.statusCode}');
      }
      final lista = jsonDecode(resp.body) as List<dynamic>;
      setState(() {
        _ventas   = lista.cast<Map<String, dynamic>>();
        _cargando = false;
      });
    } catch (e) {
      setState(() { _cargando = false; _error = 'No se pudo cargar el historial: $e'; });
    }
  }

  // ── Comprobante ───────────────────────────────────────────
  Future<void> _verDetalle(Map<String, dynamic> venta) async {
    final ventaId = int.parse(venta['id'].toString());
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VistaPreviaDialog(
        carga: cargarComprobante(HistorialVentasScreen.apiBase, ventaId),
      ),
    );
    if (datos == null || !mounted) return;
    setState(() => _comprobanteAmpliado = datos);
  }

  void _descargarComprobante(Map<String, dynamic> datos) {
    descargarDesde(
        '${HistorialVentasScreen.apiBase}/ventas/${datos['id']}/comprobante.pdf');
  }

  void _cerrarComprobante() => setState(() => _comprobanteAmpliado = null);

  // ── Helpers de fecha ──────────────────────────────────────
  bool _esHoy(DateTime? f) {
    if (f == null) return false;
    final hoy = DateTime.now();
    return f.year == hoy.year && f.month == hoy.month && f.day == hoy.day;
  }

  bool _esEsteMes(DateTime? f) {
    if (f == null) return false;
    final hoy = DateTime.now();
    return f.year == hoy.year && f.month == hoy.month;
  }

  // ── Selector de fecha ─────────────────────────────────────
  Future<void> _seleccionarFecha(bool esInicio) async {
    final inicial = esInicio
        ? (_fechaInicio ?? DateTime.now())
        : (_fechaFin   ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.accent,
              surface: AppColors.surfaceAlt,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      if (esInicio) {
        _fechaInicio = picked;
        if (_fechaFin != null && _fechaFin!.isBefore(picked)) {
          _fechaFin = null;
        }
      } else {
        _fechaFin = picked;
      }
    });
  }

  void _limpiarFiltros() {
    _busquedaCtrl.clear();
    setState(() {
      _busqueda    = '';
      _fechaInicio = null;
      _fechaFin    = null;
      _campoBusqueda = _camposBusqueda.first;
    });
  }

  // ── Filtrado combinado ────────────────────────────────────
  List<Map<String, dynamic>> get _ventasFiltradas {
    return _ventas.where((venta) {
      final texto = _busqueda.trim().toLowerCase();
      if (texto.isNotEmpty) {
        bool coincide;
        switch (_campoBusqueda) {
          case 'Producto':
            final resumen = (venta['resumen_productos'] ?? '').toString().toLowerCase();
            coincide = resumen.contains(texto);
            break;
          case 'Fecha':
            final fecha = (venta['fecha'] ?? '').toString().toLowerCase();
            coincide = fecha.contains(texto);
            break;
          case 'Codigo':
          default:
            coincide = venta['id'].toString().contains(texto);
        }
        if (!coincide) return false;
      }

      if (_fechaInicio != null || _fechaFin != null) {
        final fechaVenta = DateTime.tryParse(venta['fecha']?.toString() ?? '');
        if (fechaVenta == null) return false;
        final soloFecha = DateTime(fechaVenta.year, fechaVenta.month, fechaVenta.day);
        if (_fechaInicio != null && soloFecha.isBefore(_fechaInicio!)) return false;
        if (_fechaFin    != null && soloFecha.isAfter(_fechaFin!))     return false;
      }

      return true;
    }).toList();
  }

  // ── Exportar PDF ──────────────────────────────────────────
  Future<void> _exportarPDF() async {
    final ventas = _ventasFiltradas;
    if (ventas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay ventas para exportar con los filtros actuales.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _exportando = true);
    try {
      final ids = ventas.map((v) => v['id']).whereType<int>().toList();
      final resp = await http.post(
        Uri.parse('${HistorialVentasScreen.apiBase}/ventas/historial.pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      );
      if (resp.statusCode != 200) {
        throw Exception('Servidor: ${resp.statusCode}');
      }

      final blob = html.Blob([resp.bodyBytes], 'application/pdf');
      final url  = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'historial_ventas.pdf')
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF generado: historial_ventas.pdf (solo ventas finalizadas)'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Exportar CSV ──────────────────────────────────────────
  Future<void> _exportarCSV() async {
    final ventas = _ventasFiltradas;
    if (ventas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No hay ventas para exportar con los filtros actuales.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _exportando = true);
    try {
      // Construir CSV
      final buffer = StringBuffer();
      buffer.writeln('ID,Fecha,Estado,Cliente,Documento,Productos,Cantidad,Total');

      for (final v in ventas) {
        final id       = v['id']?.toString() ?? '';
        final fecha    = (v['fecha'] ?? '').toString().replaceAll(',', ' ');
        final estado   = (v['estado'] ?? '').toString();
        final cliente  = (v['cliente_nombre'] ?? '').toString().replaceAll(',', ' ');
        final doc      = (v['cliente_documento'] ?? '').toString();
        final resumen  = (v['resumen_productos'] ?? '').toString().replaceAll(',', ';');
        final cantidad = v['cantidad_productos']?.toString() ?? '0';
        final total    = double.tryParse(v['total'].toString())?.toStringAsFixed(2) ?? '0.00';

        buffer.writeln('"$id","$fecha","$estado","$cliente","$doc","$resumen","$cantidad","$total"');
      }

      // Nombre del archivo con rango de fechas si aplica
      String dos(int n) => n.toString().padLeft(2, '0');
      String nombreArchivo = 'ventas';
      if (_fechaInicio != null) {
        nombreArchivo += '_desde_${_fechaInicio!.year}${dos(_fechaInicio!.month)}${dos(_fechaInicio!.day)}';
      }
      if (_fechaFin != null) {
        nombreArchivo += '_hasta_${_fechaFin!.year}${dos(_fechaFin!.month)}${dos(_fechaFin!.day)}';
      }
      nombreArchivo += '.csv';

      // Descargar en el navegador
      final bytes = utf8.encode(buffer.toString());
      final blob  = html.Blob([bytes], 'text/csv;charset=utf-8');
      final url   = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', nombreArchivo)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exportadas ${ventas.length} ventas → $nombreArchivo'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ampliado = _comprobanteAmpliado;

    if (ampliado != null) {
      return AppShell(
        current: AppSection.ventas,
        apiBase: HistorialVentasScreen.apiBase,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Volver al historial',
              icon: Icon(Icons.arrow_back),
              onPressed: _cerrarComprobante,
            ),
            title: Text('Comprobante ${ampliado['numero'] ?? '#${ampliado['id']}'}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  onPressed: () => _descargarComprobante(ampliado),
                  icon: Icon(Icons.download_rounded, size: 18),
                  label: Text('Descargar comprobante'),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 760),
                  child: ComprobanteVista(datos: ampliado, grande: true),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppShell(
      current: AppSection.ventas,
      apiBase: HistorialVentasScreen.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Ventas'),
        ),
        body: BoundedContent(
          maxWidth: 960,
          child: _buildContenido(),
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: _cargarVentas,
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    final ventasFinalizadas = _ventas.where((v) => (v['estado'] ?? '') == 'finalizada');
    final ventasHoy         = _ventas.where((v) => _esHoy(DateTime.tryParse(v['fecha']?.toString() ?? '')));
    final ventasEsteMes     = _ventas.where((v) => _esEsteMes(DateTime.tryParse(v['fecha']?.toString() ?? '')));
    final totalHoy = ventasFinalizadas
        .where((v) => _esHoy(DateTime.tryParse(v['fecha']?.toString() ?? '')))
        .fold<double>(0, (s, v) => s + (double.tryParse(v['total'].toString()) ?? 0));
    final totalEsteMes = ventasFinalizadas
        .where((v) => _esEsteMes(DateTime.tryParse(v['fecha']?.toString() ?? '')))
        .fold<double>(0, (s, v) => s + (double.tryParse(v['total'].toString()) ?? 0));

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _cargarVentas,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Encabezado
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(Icons.receipt_long_outlined,
                    color: AppColors.accent, size: 18),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Historial de ventas',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  Text('Todas las ventas registradas desde el punto de venta.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildStats(ventasHoy.length, totalHoy,
              ventasEsteMes.length, totalEsteMes),
          SizedBox(height: 16),
          _buildFiltros(),
          SizedBox(height: 16),
          _buildTabla(),
        ],
      ),
    );
  }

  // ── Stats ─────────────────────────────────────────────────
  Widget _buildStats(int ventasHoy, double totalHoy,
      int ventasEsteMes, double totalEsteMes) {
    final tarjetas = [
      ('VENTAS HOY',      '$ventasHoy'),
      ('TOTAL HOY',       'S/ ${totalHoy.toStringAsFixed(2)}'),
      ('VENTAS ESTE MES', '$ventasEsteMes'),
      ('TOTAL ESTE MES',  'S/ ${totalEsteMes.toStringAsFixed(2)}'),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final columnas =
          constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 560 ? 2 : 1);
      final ancho = (constraints.maxWidth - (columnas - 1) * 12) / columnas;

      return Wrap(
        spacing: 12, runSpacing: 12,
        children: tarjetas.map((t) {
          return SizedBox(
            width: ancho,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  // ── Filtros ───────────────────────────────────────────────
  Widget _buildFiltros() {
    final hayFiltros = _busqueda.isNotEmpty ||
        _fechaInicio != null ||
        _fechaFin != null;
    final cantidadFiltrada = _ventasFiltradas.length;

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
          Row(
            children: [
              Text('Filtrar ventas',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              Spacer(),
              // Boton exportar CSV
              _exportando
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _ventas.isEmpty ? null : _exportarPDF,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: BorderSide(
                                color: AppColors.accent.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: Icon(Icons.picture_as_pdf_outlined, size: 15),
                          label: Text('Exportar PDF', style: TextStyle(fontSize: 12)),
                        ),
                        SizedBox(width: 8),
                        FilledButton.icon(
                      onPressed: _ventas.isEmpty ? null : _exportarCSV,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                        foregroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Icons.download_outlined, size: 15),
                      label: Text(
                        hayFiltros
                            ? 'Exportar ($cantidadFiltrada)'
                            : 'Exportar todo',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                      ],
                    ),
            ],
          ),
          SizedBox(height: 10),

          // Busqueda por texto + selector de campo
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busquedaCtrl,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por $_campoBusqueda...',
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
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
              SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _campoBusqueda,
                    dropdownColor: AppColors.surfaceAlt,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    icon: Icon(Icons.expand_more,
                        size: 18, color: AppColors.textMuted),
                    items: _camposBusqueda
                        .map((c) => DropdownMenuItem(
                            value: c, child: Text('Por $c')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _campoBusqueda = v);
                    },
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),

          // Rango de fechas
          Row(
            children: [
              Expanded(
                child: _BotonFecha(
                  etiqueta: 'Desde',
                  fecha: _fechaInicio,
                  onTap: () => _seleccionarFecha(true),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _BotonFecha(
                  etiqueta: 'Hasta',
                  fecha: _fechaFin,
                  onTap: () => _seleccionarFecha(false),
                ),
              ),
              if (hayFiltros) ...[
                SizedBox(width: 10),
                TextButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: Icon(Icons.filter_alt_off_outlined, size: 15),
                  label: Text('Limpiar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Tabla ─────────────────────────────────────────────────
  Widget _buildTabla() {
    final ventas = _ventasFiltradas;

    if (ventas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded,
                  color: AppColors.textMuted, size: 28),
              SizedBox(height: 12),
              Text(
                _ventas.isEmpty
                    ? 'Todavia no hay ventas registradas'
                    : 'Ninguna venta coincide con los filtros',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final anchoTabla =
            constraints.maxWidth > 840 ? constraints.maxWidth : 840.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: anchoTabla,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilaEncabezado(),
                Divider(color: AppColors.border, height: 1),
                ...ventas.map((v) => _buildFilaVenta(v)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFilaEncabezado() {
    final estilo = TextStyle(
        color: AppColors.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text('#', style: estilo)),
          Expanded(flex: 3, child: Text('VENTA', style: estilo)),
          Expanded(flex: 4, child: Text('PRODUCTOS', style: estilo)),
          Expanded(flex: 3, child: Text('FECHA Y HORA', style: estilo)),
          SizedBox(
              width: 90,
              child: Text('TOTAL', style: estilo, textAlign: TextAlign.right)),
          SizedBox(
              width: 130,
              child: Text('COMPROBANTE', style: estilo, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildFilaVenta(Map<String, dynamic> venta) {
    final total        = double.tryParse(venta['total'].toString()) ?? 0;
    final estado       = (venta['estado'] ?? '').toString();
    final esFinalizada = estado == 'finalizada';
    final infoEstado   = EstadoVenta.de(estado);
    final color        = infoEstado.color;
    final fecha        = DateTime.tryParse(venta['fecha']?.toString() ?? '');
    final resumen      = (venta['resumen_productos'] as String?)?.trim();
    final cantidad     = venta['cantidad_productos'];
    final cliente      = (venta['cliente_nombre'] as String?)?.trim();

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DetalleVentaScreen(
              venta: venta, apiBase: HistorialVentasScreen.apiBase),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text('#${venta['id']}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5)),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Icon(
                      infoEstado.icono,
                      size: 14,
                      color: color),
                  SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            (cliente == null || cliente.isEmpty)
                                ? 'Venta en tienda'
                                : cliente,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                        Text(infoEstado.etiqueta,
                            style: TextStyle(color: color, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                (resumen == null || resumen.isEmpty) ? 'Sin productos' : resumen,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fecha != null ? _formatearFecha(fecha) : '—',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12),
                  ),
                  Text(
                    fecha != null ? _tiempoRelativo(fecha) : '',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('S/ ${total.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5)),
                  Text('$cantidad prod.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 10.5)),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Center(
                child: esFinalizada
                    ? OutlinedButton.icon(
                        onPressed: () => _verDetalle(venta),
                        icon: Icon(Icons.receipt_long_outlined, size: 15),
                        label: Text('Ver detalle'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      )
                    : Text('Sin comprobante',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatearFecha(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
  }

  String _tiempoRelativo(DateTime f) {
    final d = DateTime.now().difference(f);
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours   < 24) return 'hace ${d.inHours} h';
    if (d.inDays    < 7)  return 'hace ${d.inDays} dias';
    return 'hace ${(d.inDays / 7).floor()} semanas';
  }
}

// ══════════════════════════════════════════════════════════════
//  POPUP — vista previa del comprobante. Al hacer clic devuelve los
//  datos para abrir la vista grande.
// ══════════════════════════════════════════════════════════════
class _VistaPreviaDialog extends StatelessWidget {
  final Future<Map<String, dynamic>> carga;

  const _VistaPreviaDialog({required this.carga});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: FutureBuilder<Map<String, dynamic>>(
          future: carga,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return SizedBox(
                height: 200,
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent)),
              );
            }
            if (snap.hasError) {
              final error = snap.error.toString().replaceFirst('Exception: ', '');
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No se pudo cargar el comprobante: $error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary)),
                    SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cerrar'),
                    ),
                  ],
                ),
              );
            }
            final datos = snap.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Tooltip(
                      message: 'Clic para ampliar',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.zoomIn,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, datos),
                          child: ComprobanteVista(datos: datos),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Row(
                    children: [
                      Icon(Icons.zoom_in_rounded,
                          size: 16, color: AppColors.textMuted),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text('Haz clic en el comprobante para ampliarlo',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11.5)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cerrar'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  WIDGET AUXILIAR — botón selector de fecha
// ══════════════════════════════════════════════════════════════
class _BotonFecha extends StatelessWidget {
  final String    etiqueta;
  final DateTime? fecha;
  final VoidCallback onTap;

  const _BotonFecha({
    required this.etiqueta,
    required this.fecha,
    required this.onTap,
  });

  String _formatear(DateTime f) {
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    final seleccionado = fecha != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: seleccionado
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: seleccionado
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14,
                color: seleccionado ? AppColors.accent : AppColors.textMuted),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiqueta.toUpperCase(),
                    style: TextStyle(
                      color: seleccionado
                          ? AppColors.accent
                          : AppColors.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    seleccionado ? _formatear(fecha!) : 'Seleccionar',
                    style: TextStyle(
                      color: seleccionado
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontSize: 12.5,
                      fontWeight: seleccionado
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}