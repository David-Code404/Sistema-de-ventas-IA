import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/session.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/bounded_content.dart';
import 'detalle_venta_screen.dart';

/// Panel de estadisticas de ventas — solo para el Administrador.
class DashboardScreen extends StatefulWidget {
  DashboardScreen({super.key});

  static const String apiBase = AppConfig.apiBase;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

const _rangos = [
  (1, 'Hoy'),
  (7, '7 dias'),
  (30, '30 dias'),
  (0, 'Todo'),
];

const _colorMetodo = {
  'efectivo': AppColors.accent,
  'tarjeta': Color(0xFF38BDF8),
  'qr': Color(0xFFA78BFA),
};

const _iconoMetodo = {
  'efectivo': Icons.payments_outlined,
  'tarjeta': Icons.credit_card_outlined,
  'qr': Icons.qr_code_2_rounded,
};

const _nombreMetodo = {
  'efectivo': 'Efectivo',
  'tarjeta': 'Tarjeta',
  'qr': 'QR',
};

double _n(dynamic v) => double.tryParse('$v') ?? 0;
String _bs(dynamic v) => 'Bs. ${_n(v).toStringAsFixed(2)}';
String _pl(dynamic v, String uno, String varios) =>
    '${_n(v).toInt()} ${_n(v).toInt() == 1 ? uno : varios}';

String _fechaHora(String? iso) {
  final f = DateTime.tryParse(iso ?? '');
  if (f == null) return '-';
  String d(int x) => x.toString().padLeft(2, '0');
  return '${d(f.day)}/${d(f.month)} ${d(f.hour)}:${d(f.minute)}';
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _dias = 30;
  Map<String, dynamic>? _datos;
  bool _cargando = true;
  String? _error;
  bool _compacto = false;
  int _nBarras1 = 4;
  int _nBarras2 = 5;
  int _nClientes = 3;
  int _nUltimas = 5;

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
      final resp = await http.get(Uri.parse(
          '${DashboardScreen.apiBase}/dashboard/estadisticas?dias=$_dias'));
      if (resp.statusCode != 200) {
        throw Exception('El backend respondio ${resp.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _datos = jsonDecode(resp.body) as Map<String, dynamic>;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las estadisticas: $e';
      });
    }
  }

  List<Map<String, dynamic>> _lista(String clave, [int? maximo]) {
    final todo = ((_datos?[clave] as List?) ?? []).cast<Map<String, dynamic>>();
    return maximo == null ? todo : todo.take(maximo).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      current: AppSection.dashboard,
      apiBase: DashboardScreen.apiBase,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text('Dashboard')),
        body: !Session.esAdmin
            ? Center(
                child: Text('Esta seccion es solo para administradores.',
                    style: TextStyle(color: AppColors.textSecondary)))
            : _contenido(),
      ),
    );
  }

  Widget _contenido() {
    if (_cargando && _datos == null) {
      return Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_error != null && _datos == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      );
    }

    final resumen = (_datos!['resumen'] as Map).cast<String, dynamic>();
    final ventas = _n(resumen['ventas']).toInt();

    return LayoutBuilder(builder: (context, c) {
      final ajustada = ventas > 0 && c.maxWidth >= 1000 && c.maxHeight >= 600;
      _compacto = ajustada;
      return ajustada ? _vistaAjustada(resumen) : _vistaScroll(resumen, ventas);
    });
  }

  Widget _vistaScroll(Map<String, dynamic> resumen, int ventas) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _cargar,
      child: BoundedContent(
        maxWidth: 1180,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _encabezado(),
            SizedBox(height: 16),
            _kpis(resumen),
            SizedBox(height: 16),
            if (ventas == 0)
              _panel(
                'Sin ventas en este periodo',
                Icons.info_outline,
                Text(
                    'Todavia no hay ventas finalizadas en el rango elegido. Prueba con "Todo".',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              )
            else ...[
              _panel('Ingresos por dia', Icons.bar_chart_rounded, _graficoDias()),
              SizedBox(height: 16),
              _fila2(
                _panel('Metodos de pago', Icons.account_balance_wallet_outlined,
                    _porMetodo()),
                _panel('Ventas por cajero', Icons.badge_outlined, _porCajero()),
              ),
              SizedBox(height: 16),
              _fila2(
                _panel('Productos mas vendidos', Icons.local_fire_department_outlined,
                    _topProductos()),
                _panel('Ventas por categoria', Icons.category_outlined,
                    _porCategoria()),
              ),
              SizedBox(height: 16),
              _fila2(
                _panel('Clientes y facturas', Icons.groups_2_outlined,
                    _clientes(resumen)),
                _panel('Horas pico', Icons.schedule_rounded, _horasPico()),
              ),
              SizedBox(height: 16),
              _panel('Ultimas ventas', Icons.receipt_long_outlined, _ultimas()),
            ],
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Vista ajustada a la pantalla (sin scroll) ───────────────
  Widget _vistaAjustada(Map<String, dynamic> resumen) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _encabezado(),
          SizedBox(height: 10),
          _kpis(resumen),
          SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final interior = c.maxHeight - 54;
              _nBarras1 = (interior / 40).floor().clamp(1, 8);
              return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 6,
                  child: _panelFijo(
                    'Ingresos por dia',
                    Icons.bar_chart_rounded,
                    Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (_, c) => _graficoDias(
                                alto: (c.maxHeight - 28).clamp(50.0, 420.0)),
                          ),
                        ),
                        SizedBox(height: 6),
                        _horasChips(),
                      ],
                    ),
                    scroll: false,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: _panelFijo('Metodos de pago',
                      Icons.account_balance_wallet_outlined, _porMetodo()),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: _panelFijo(
                      'Ventas por cajero', Icons.badge_outlined, _porCajero()),
                ),
              ],
            );
            }),
          ),
          SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final interior = c.maxHeight - 54;
              _nBarras2 = (interior / 40).floor().clamp(1, 8);
              _nClientes = ((interior - 108) / 48).floor().clamp(1, 5);
              _nUltimas = (interior / 44).floor().clamp(2, 8);
              return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: _panelFijo('Productos mas vendidos',
                      Icons.local_fire_department_outlined, _topProductos()),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: _panelFijo('Ventas por categoria',
                      Icons.category_outlined, _porCategoria()),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: _panelFijo('Clientes y facturas',
                      Icons.groups_2_outlined, _clientes(resumen)),
                ),
                SizedBox(width: 10),
                Expanded(
                  flex: 5,
                  child: _panelFijo('Ultimas ventas',
                      Icons.receipt_long_outlined, _ultimas()),
                ),
              ],
            );
            }),
          ),
        ],
      ),
    );
  }

  Widget _panelFijo(String titulo, IconData icono, Widget hijo,
      {bool scroll = true}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, size: 15, color: AppColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(titulo.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7)),
              ),
            ],
          ),
          SizedBox(height: 10),
          Expanded(
            child: scroll
                ? ClipRect(
                    child: SingleChildScrollView(
                      physics: NeverScrollableScrollPhysics(),
                      child: hijo,
                    ),
                  )
                : hijo,
          ),
        ],
      ),
    );
  }

  Widget _horasChips() {
    final filas = _lista('horas_pico');
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
        Text('Horas pico:',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
        for (var i = 0; i < filas.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.tagColorFor(i).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.tagColorFor(i).withValues(alpha: 0.4)),
            ),
            child: Text(
                '${hh(_n(filas[i]['hora']).toInt())}  ·  ${_pl(filas[i]['ventas'], 'venta', 'ventas')}',
                style: TextStyle(
                    color: AppColors.tagColorFor(i),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  // ── Encabezado y filtro de rango ────────────────────────────
  Widget _encabezado() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Estadisticas de ventas',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 2),
            Text('Resumen de las ventas finalizadas.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in _rangos) ...[
              _chipRango(r.$1, r.$2),
              SizedBox(width: 6),
            ],
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargar,
              icon: Icon(Icons.refresh_rounded,
                  size: 19, color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _chipRango(int dias, String etiqueta) {
    final activo = _dias == dias;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (_dias == dias) return;
        setState(() => _dias = dias);
        _cargar();
      },
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

  // ── Tarjetas de resumen ─────────────────────────────────────
  Widget _kpis(Map<String, dynamic> r) {
    final ventas = _n(r['ventas']).toInt();
    final conFactura = _n(r['con_factura']).toInt();
    final pctFactura = ventas == 0 ? 0 : (conFactura * 100 / ventas);

    final tarjetas = <(String, String, IconData, bool)>[
      ('INGRESOS', _bs(r['ingresos']), Icons.payments_outlined, true),
      ('VENTAS', '$ventas', Icons.point_of_sale_outlined, false),
      ('TICKET PROMEDIO', _bs(r['ticket_promedio']), Icons.receipt_outlined, false),
      ('UNIDADES VENDIDAS', '${_n(r['unidades']).toInt()}',
          Icons.shopping_bag_outlined, false),
      ('VENTA MAS ALTA', _bs(r['venta_mayor']), Icons.trending_up_rounded, false),
      ('CON FACTURA', '$conFactura  (${pctFactura.toStringAsFixed(0)}%)',
          Icons.description_outlined, false),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columnas = c.maxWidth > 980 ? 6 : (c.maxWidth > 640 ? 3 : 2);
      final ancho = (c.maxWidth - (columnas - 1) * 10) / columnas;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in tarjetas)
            SizedBox(
              width: ancho,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.$4
                      ? AppColors.accent.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: t.$4
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(t.$3,
                            size: 14,
                            color: t.$4 ? AppColors.accent : AppColors.textMuted),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(t.$1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4)),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(t.$2,
                          style: TextStyle(
                              color: t.$4
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  // ── Contenedores ────────────────────────────────────────────
  Widget _panel(String titulo, IconData icono, Widget hijo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Text(titulo.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7)),
            ],
          ),
          SizedBox(height: 14),
          hijo,
        ],
      ),
    );
  }

  Widget _fila2(Widget a, Widget b) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 820) {
        return Column(children: [a, SizedBox(height: 16), b]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          SizedBox(width: 16),
          Expanded(child: b),
        ],
      );
    });
  }

  // ── Grafico de ingresos por dia ─────────────────────────────
  Widget _graficoDias({double alto = 140}) {
    final filas = _lista('por_dia');
    final porDia = <String, Map<String, dynamic>>{
      for (final f in filas) '${f['dia']}'.substring(0, 10): f,
    };

    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);
    DateTime inicio;
    if (_dias > 0) {
      inicio = hoySolo.subtract(Duration(days: _dias - 1));
    } else {
      inicio = DateTime.parse(porDia.keys.reduce((a, b) => a.compareTo(b) < 0 ? a : b));
      if (hoySolo.difference(inicio).inDays > 30) {
        inicio = hoySolo.subtract(Duration(days: 30));
      }
    }

    final dias = <DateTime>[];
    for (var d = inicio; !d.isAfter(hoySolo); d = d.add(Duration(days: 1))) {
      dias.add(d);
    }

    String clave(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    var maximo = 0.0;
    for (final d in dias) {
      final v = _n(porDia[clave(d)]?['ingresos']);
      if (v > maximo) maximo = v;
    }
    if (maximo == 0) maximo = 1;

    return Column(
      children: [
        SizedBox(
          height: alto + 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in dias)
                Expanded(
                  child: Builder(builder: (_) {
                    final f = porDia[clave(d)];
                    final v = _n(f?['ingresos']);
                    final altura = v == 0 ? 3.0 : (v / maximo * alto).clamp(6.0, alto);
                    return Tooltip(
                      message:
                          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}: ${_bs(v)} (${_n(f?['ventas']).toInt()} ventas)',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height: altura,
                            decoration: BoxDecoration(
                              color: v == 0
                                  ? AppColors.border
                                  : AppColors.accent,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
        SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < dias.length; i++)
              Expanded(
                child: Center(
                  child: Text(
                    (dias.length <= 10 || i == 0 || i == dias.length - 1 || i % 5 == 0)
                        ? '${dias[i].day}/${dias[i].month}'
                        : '',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 9.5),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Barras horizontales reutilizables ───────────────────────
  Widget _barraFila({
    required Widget etiqueta,
    required double valor,
    required double maximo,
    required Color color,
    required String detalle,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: _compacto ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: etiqueta),
              Text(detalle,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: maximo == 0 ? 0 : (valor / maximo).clamp(0.0, 1.0),
              minHeight: _compacto ? 6 : 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Text _titulo(String t) => Text(t,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600));

  Widget _porMetodo() {
    final filas = _lista('por_metodo');
    final total = filas.fold<double>(0, (s, f) => s + _n(f['ingresos']));
    return Column(
      children: [
        for (final f in filas)
          _barraFila(
            etiqueta: Row(children: [
              Icon(_iconoMetodo['${f['metodo']}'] ?? Icons.payments_outlined,
                  size: 16,
                  color: _colorMetodo['${f['metodo']}'] ?? AppColors.accent),
              SizedBox(width: 8),
              _titulo(_nombreMetodo['${f['metodo']}'] ?? '${f['metodo']}'),
            ]),
            valor: _n(f['ingresos']),
            maximo: total,
            color: _colorMetodo['${f['metodo']}'] ?? AppColors.accent,
            detalle:
                '${_pl(f['ventas'], 'venta', 'ventas')}  ·  ${_bs(f['ingresos'])}  ·  ${total == 0 ? 0 : (_n(f['ingresos']) * 100 / total).toStringAsFixed(0)}%',
          ),
      ],
    );
  }

  Widget _porCajero() {
    final filas = _lista('por_cajero', _compacto ? _nBarras1 : null);
    final total = filas.fold<double>(0, (s, f) => s + _n(f['ingresos']));
    final haySinRegistrar = filas.any((f) => f['cajero'] == 'Sin registrar');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in filas)
          _barraFila(
            etiqueta: Row(children: [
              Icon(Icons.person_outline,
                  size: 16, color: AppColors.warning),
              SizedBox(width: 8),
              _titulo('${f['cajero']}'),
            ]),
            valor: _n(f['ingresos']),
            maximo: total,
            color: AppColors.warning,
            detalle:
                '${_pl(f['ventas'], 'venta', 'ventas')}  ·  ${_bs(f['ingresos'])}',
          ),
        if (haySinRegistrar)
          Text(
              '"Sin registrar": ventas hechas antes de que el sistema guardara el cajero.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _topProductos() {
    final filas = _lista('top_productos', _compacto ? _nBarras2 : null);
    final maximo =
        filas.fold<double>(0, (m, f) => _n(f['unidades']) > m ? _n(f['unidades']) : m);
    return Column(
      children: [
        for (var i = 0; i < filas.length; i++)
          _barraFila(
            etiqueta: Row(children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 8),
              Expanded(child: _titulo('${filas[i]['nombre']}')),
            ]),
            valor: _n(filas[i]['unidades']),
            maximo: maximo,
            color: AppColors.accent,
            detalle:
                '${_n(filas[i]['unidades']).toInt()} uds  ·  ${_bs(filas[i]['ingresos'])}',
          ),
      ],
    );
  }

  Widget _porCategoria() {
    final filas = _lista('por_categoria', _compacto ? _nBarras2 : null);
    final maximo =
        filas.fold<double>(0, (m, f) => _n(f['ingresos']) > m ? _n(f['ingresos']) : m);
    return Column(
      children: [
        for (var i = 0; i < filas.length; i++)
          _barraFila(
            etiqueta: _titulo('${filas[i]['categoria']}'),
            valor: _n(filas[i]['ingresos']),
            maximo: maximo,
            color: AppColors.tagColorFor(i),
            detalle:
                '${_n(filas[i]['unidades']).toInt()} uds  ·  ${_bs(filas[i]['ingresos'])}',
          ),
      ],
    );
  }

  // ── Clientes y facturas ─────────────────────────────────────
  Widget _clientes(Map<String, dynamic> resumen) {
    final ventas = _n(resumen['ventas']).toInt();
    final conFactura = _n(resumen['con_factura']).toInt();
    final clientes = _lista('top_clientes', _compacto ? _nClientes : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _datoChico('Con factura', '$conFactura', AppColors.accent),
            SizedBox(width: 10),
            _datoChico('Sin factura', '${ventas - conFactura}', AppColors.textSecondary),
          ],
        ),
        SizedBox(height: 14),
        Text('CLIENTES CON MAS COMPRAS',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        SizedBox(height: 8),
        if (clientes.isEmpty)
          Text('Aun no hay ventas con datos de cliente.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
        else
          for (final c in clientes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(Icons.person_pin_outlined,
                      size: 16, color: AppColors.textMuted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _titulo('${c['cliente']}'),
                        if (c['documento'] != null)
                          Text('NIT / CI ${c['documento']}',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text(
                      '${_pl(c['compras'], 'compra', 'compras')}  ·  ${_bs(c['total'])}',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
      ],
    );
  }

  Widget _datoChico(String etiqueta, String valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            SizedBox(height: 4),
            Text(valor,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  // ── Horas pico ──────────────────────────────────────────────
  Widget _horasPico() {
    final filas = _lista('horas_pico');
    String hh(int h) => '${h.toString().padLeft(2, '0')}:00';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Las horas del dia con mas ventas.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        SizedBox(height: 12),
        for (var i = 0; i < filas.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.tagColorFor(i).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${i + 1}',
                      style: TextStyle(
                          color: AppColors.tagColorFor(i),
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                ),
                SizedBox(width: 10),
                Text('${hh(_n(filas[i]['hora']).toInt())} - ${hh(_n(filas[i]['hora']).toInt() + 1)}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Spacer(),
                Text(_pl(filas[i]['ventas'], 'venta', 'ventas'),
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    );
  }

  // ── Ultimas ventas ──────────────────────────────────────────
  Widget _ultimas() {
    final filas = _lista('ultimas', _compacto ? _nUltimas : null);
    if (_compacto) return _ultimasCompactas(filas);
    return Column(
      children: [
        for (var i = 0; i < filas.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetalleVentaScreen(
                  venta: {
                    'id': filas[i]['id'],
                    'estado': 'finalizada',
                    'total': filas[i]['total'],
                    'fecha': filas[i]['creado_en'],
                  },
                  apiBase: DashboardScreen.apiBase,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text('#${filas[i]['id']}',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fechaHora(filas[i]['creado_en']?.toString()),
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12.5)),
                        Text('Cajero: ${filas[i]['cajero']}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                        filas[i]['cliente_nombre'] != null
                            ? '${filas[i]['cliente_nombre']}'
                            : 'Sin datos de cliente',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: filas[i]['cliente_nombre'] != null
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontSize: 12.5)),
                  ),
                  _chipMetodo('${filas[i]['metodo_pago']}'),
                  SizedBox(width: 8),
                  Icon(
                    _n(filas[i]['factura']) == 1
                        ? Icons.description_rounded
                        : Icons.description_outlined,
                    size: 16,
                    color: _n(filas[i]['factura']) == 1
                        ? AppColors.accent
                        : AppColors.textMuted.withValues(alpha: 0.5),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(_bs(filas[i]['total']),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _ultimasCompactas(List<Map<String, dynamic>> filas) {
    return Column(
      children: [
        for (var i = 0; i < filas.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DetalleVentaScreen(
                  venta: {
                    'id': filas[i]['id'],
                    'estado': 'finalizada',
                    'total': filas[i]['total'],
                    'fecha': filas[i]['creado_en'],
                  },
                  apiBase: DashboardScreen.apiBase,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text('#${filas[i]['id']}',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fechaHora(filas[i]['creado_en']?.toString()),
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                        Text(
                            filas[i]['cliente_nombre'] != null
                                ? '${filas[i]['cajero']}  ·  ${filas[i]['cliente_nombre']}'
                                : '${filas[i]['cajero']}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  _chipMetodo('${filas[i]['metodo_pago']}'),
                  if (_n(filas[i]['factura']) == 1) ...[
                    SizedBox(width: 5),
                    Icon(Icons.description_rounded,
                        size: 14, color: AppColors.accent),
                  ],
                  SizedBox(width: 6),
                  Text(_bs(filas[i]['total']),
                      style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _chipMetodo(String metodo) {
    final color = _colorMetodo[metodo] ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(_nombreMetodo[metodo] ?? metodo,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
