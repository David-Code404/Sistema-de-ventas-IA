import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme/app_colors.dart';

class _ProductoStockBajo {
  final int id;
  final String nombre;
  final int stock;
  final int minimo;

  _ProductoStockBajo({
    required this.id,
    required this.nombre,
    required this.stock,
    required this.minimo,
  });

  factory _ProductoStockBajo.fromJson(Map<String, dynamic> j) =>
      _ProductoStockBajo(
        id: j['id'] as int,
        nombre: (j['nombre'] ?? '').toString(),
        stock: (j['stock'] as num).toInt(),
        minimo: (j['stock_minimo'] as num).toInt(),
      );

  bool get agotado => stock <= 0;
}

/// Alerta visual de stock bajo para la pantalla de venta.
///
/// Consulta `GET /inventario/stock-bajo` cada pocos segundos y muestra un
/// aviso con los productos que llegaron (o bajaron de) su stock mínimo.
/// Si no hay ninguno no ocupa espacio. El aviso se puede descartar y vuelve
/// a aparecer solo cuando cambia la lista o alguna cantidad.
class StockBajoBanner extends StatefulWidget {
  final String apiBase;
  final Duration cadaCuanto;

  const StockBajoBanner({
    super.key,
    required this.apiBase,
    this.cadaCuanto = const Duration(seconds: 10),
  });

  @override
  State<StockBajoBanner> createState() => _StockBajoBannerState();
}

class _StockBajoBannerState extends State<StockBajoBanner> {
  Timer? _timer;
  List<_ProductoStockBajo> _items = [];
  String? _firmaDescartada;
  bool _abierto = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(widget.cadaCuanto, (_) => _cargar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await http
          .get(Uri.parse('${widget.apiBase}/inventario/stock-bajo'));
      if (r.statusCode != 200 || !mounted) return;
      final lista = (jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>)
          .map((e) => _ProductoStockBajo.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() => _items = lista);
    } catch (_) {
      // Si falla una consulta puntual se conserva lo último y se reintenta.
    }
  }

  String get _firma => _items.map((e) => '${e.id}:${e.stock}').join(',');

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty || _firma == _firmaDescartada) {
      return SizedBox.shrink();
    }

    final agotados = _items.where((e) => e.agotado).length;
    final bajos = _items.length - agotados;
    final color = agotados > 0 ? AppColors.danger : AppColors.warning;

    final partes = <String>[
      if (agotados > 0)
        agotados == 1 ? '1 producto agotado' : '$agotados productos agotados',
      if (bajos > 0)
        bajos == 1 ? '1 con stock bajo' : '$bajos con stock bajo',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _abierto = !_abierto),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: color, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Alerta de stock: ${partes.join(' · ')}',
                            style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(_abierto ? 'Ocultar detalle' : 'Ver detalle',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 11.5)),
                        Icon(
                            _abierto
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            color: AppColors.textSecondary,
                            size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Descartar hasta que cambie el stock',
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary),
                onPressed: () => setState(() => _firmaDescartada = _firma),
              ),
            ],
          ),
          if (_abierto)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                children: [
                  for (final p in _items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(p.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12.5)),
                          ),
                          Text(
                            p.agotado
                                ? 'Agotado'
                                : 'Quedan ${p.stock} · mínimo ${p.minimo}',
                            style: TextStyle(
                                color: p.agotado
                                    ? AppColors.danger
                                    : AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}