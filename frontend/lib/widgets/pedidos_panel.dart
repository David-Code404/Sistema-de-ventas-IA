import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/estado_venta.dart';
import '../models/pedidos_monitor.dart';
import '../models/session.dart';
import '../models/whatsapp.dart';
import '../theme/app_colors.dart';
import 'bounded_content.dart';

/// Pedidos en linea de los clientes, para administrador y cajero:
///   - Pendientes: el cajero los prepara y los marca como listos
///     (al marcarlos se descuenta el stock).
///   - Listos para recoger: ya preparados, esperando al cliente.
/// Se actualiza sola cuando llegan pedidos nuevos (PedidosMonitor).
/// Va dentro de PedidosPendientesScreen (que agrega el sidebar).
class PedidosPanel extends StatefulWidget {
  final String apiBase;

  const PedidosPanel({super.key, required this.apiBase});

  @override
  State<PedidosPanel> createState() => _PedidosPanelState();
}

class _PedidosPanelState extends State<PedidosPanel> {
  final _monitor = PedidosMonitor.instance;

  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _listos = [];
  bool _cargando = true;
  String? _error;
  final Set<int> _marcando = {};

  int _versionVista = -1;
  int _ultimoVisto = 0;

  @override
  void initState() {
    super.initState();
    _monitor.addListener(_alCambiarMonitor);
    _cargar();
  }

  @override
  void dispose() {
    _monitor.removeListener(_alCambiarMonitor);
    super.dispose();
  }

  void _alCambiarMonitor() {
    if (_monitor.version == _versionVista) return;
    final nuevo = _monitor.ultimoPendienteId > _ultimoVisto && _ultimoVisto > 0;
    _cargar(silencioso: true);
    if (nuevo && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Llego un pedido nuevo (#${_monitor.ultimoPendienteId}).'),
            backgroundColor: AppColors.warning,
          ),
        );
    }
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final respuestas = await Future.wait([
        http.get(Uri.parse('${widget.apiBase}/pedidos/pendientes')),
        http.get(Uri.parse('${widget.apiBase}/pedidos/listos')),
      ]).timeout(const Duration(seconds: 15));
      for (final r in respuestas) {
        if (r.statusCode != 200) throw Exception('Backend: ${r.statusCode}');
      }
      List<Map<String, dynamic>> leer(http.Response r) =>
          (jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>).cast<Map<String, dynamic>>();
      final pendientes = leer(respuestas[0]);
      final listos = leer(respuestas[1]);
      if (!mounted) return;
      setState(() {
        _pendientes = pendientes;
        _listos = listos;
        _cargando = false;
        _error = null;
        _versionVista = _monitor.version;
        for (final p in pendientes) {
          final id = (p['id'] as num).toInt();
          if (id > _ultimoVisto) _ultimoVisto = id;
        }
        if (_monitor.ultimoPendienteId > _ultimoVisto) {
          _ultimoVisto = _monitor.ultimoPendienteId;
        }
      });
    } catch (e) {
      if (!mounted) return;
      // En la actualizacion automatica se conserva la lista que ya se ve
      if (silencioso && (_pendientes.isNotEmpty || _listos.isNotEmpty)) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los pedidos. Revisa la conexion con el servidor.';
      });
    }
  }

  Future<void> _marcarListo(Map<String, dynamic> p) async {
    final id = (p['id'] as num).toInt();
    final items = (p['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceAlt,
            title: Text('Marcar pedido #$id como listo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se descontara del inventario:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                SizedBox(height: 8),
                for (final it in items)
                  Text(
                    '• ${it['cantidad']} x ${it['nombre']}',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  ),
                SizedBox(height: 12),
                Text(
                  'Esta accion no se puede deshacer.',
                  style: TextStyle(color: AppColors.warning, fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Marcar como listo'),
              ),
            ],
          ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _marcando.add(id));
    String mensaje;
    Color color = AppColors.danger;
    var exito = false;
    try {
      final resp = await http
          .post(
            Uri.parse('${widget.apiBase}/pedidos/$id/listo'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'usuario_id': Session.usuarioId}),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        mensaje = 'Pedido #$id listo para recoger. Stock descontado.';
        color = AppColors.accent;
        exito = true;
      } else {
        String? detalle;
        try {
          detalle =
              (jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>)['detail']
                  ?.toString();
        } catch (_) {}
        mensaje = detalle ?? 'No se pudo marcar el pedido (${resp.statusCode}).';
      }
    } on TimeoutException {
      mensaje = 'El servidor tarda en responder. Intenta de nuevo.';
    } catch (_) {
      mensaje = 'Sin conexion con el servidor. Intenta de nuevo.';
    }
    if (!mounted) return;
    setState(() => _marcando.remove(id));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
    // El contador del boton Pedidos baja en el momento, sin esperar al sondeo
    _monitor.iniciar(widget.apiBase);
    await Future.wait([_cargar(silencioso: true), _monitor.actualizar()]);
    if (exito && mounted) await _ofrecerWhatsApp({...p, 'estado': 'listo'});
  }

  // ── Aviso por WhatsApp ──────────────────────────────────────
  static const _verdeWhatsApp = Color(0xFF25D366);

  /// Despues de marcar como listo: muestra el mensaje y ofrece abrir WhatsApp.
  Future<void> _ofrecerWhatsApp(Map<String, dynamic> p) async {
    final enlace = WhatsApp.enlacePedidoListo(p);
    final texto = WhatsApp.mensajePedidoListo(p);
    final telefono = (p['cliente_telefono'] ?? '').toString();
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceAlt,
            title: Text('Pedido #${p['id']} listo para recoger'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    enlace != null
                        ? 'Avisa al cliente por WhatsApp ($telefono). Se abrira el chat con este mensaje; solo pulsa Enviar:'
                        : 'El telefono "$telefono" no sirve para WhatsApp. Puedes copiar el mensaje y avisarle por otro medio:',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _verdeWhatsApp.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _verdeWhatsApp.withValues(alpha: 0.35)),
                    ),
                    child: SelectableText(
                      texto,
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: texto));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _aviso('Mensaje copiado');
                },
                icon: Icon(Icons.copy_rounded, size: 16),
                label: Text('Copiar mensaje'),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Ahora no')),
              if (enlace != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _verdeWhatsApp,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    WhatsApp.abrir(enlace);
                    Navigator.pop(ctx);
                  },
                  icon: Icon(Icons.chat_outlined, size: 17),
                  label: Text('Avisar por WhatsApp'),
                ),
            ],
          ),
    );
  }

  /// Boton de los pedidos listos: abre WhatsApp directamente.
  void _avisarWhatsApp(Map<String, dynamic> p) {
    final enlace = WhatsApp.enlacePedidoListo(p);
    if (enlace == null) {
      _ofrecerWhatsApp(p); // explica por que no se puede y permite copiar
      return;
    }
    WhatsApp.abrir(enlace);
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  // ── Formato ─────────────────────────────────────────────────
  String _dos(int n) => n.toString().padLeft(2, '0');

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '-';
    final hace = DateTime.now().difference(d);
    final rel =
        hace.inMinutes < 1
            ? 'recien'
            : hace.inMinutes < 60
            ? 'hace ${hace.inMinutes} min'
            : hace.inHours < 24
            ? 'hace ${hace.inHours} h'
            : 'hace ${hace.inDays} d';
    return '${_dos(d.day)}/${_dos(d.month)} ${_dos(d.hour)}:${_dos(d.minute)} · $rel';
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Pedidos'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              icon: Icon(Icons.refresh_rounded),
              onPressed: _cargando ? null : () => _cargar(),
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.accent,
            tabs: [
              Tab(text: 'Pendientes (${_pendientes.length})'),
              Tab(text: 'Listos para recoger (${_listos.length})'),
            ],
          ),
        ),
        body: BoundedContent(
          maxWidth: 900,
          child:
              _cargando && _pendientes.isEmpty && _listos.isEmpty
                  ? Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _error != null
                  ? _vistaError()
                  : TabBarView(
                    children: [
                      _lista(
                        _pendientes,
                        vacio: 'No hay pedidos pendientes.',
                        ayuda: 'Los pedidos nuevos apareceran aqui automaticamente.',
                      ),
                      _lista(
                        _listos,
                        vacio: 'No hay pedidos listos para recoger.',
                        ayuda: 'Marca un pedido pendiente como listo cuando este preparado.',
                      ),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _cargar(),
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lista(
    List<Map<String, dynamic>> pedidos, {
    required String vacio,
    required String ayuda,
  }) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => _cargar(silencioso: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (pedidos.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, color: AppColors.textMuted, size: 36),
                  SizedBox(height: 10),
                  Text(vacio, style: TextStyle(color: AppColors.textPrimary)),
                  SizedBox(height: 4),
                  Text(
                    ayuda,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                ],
              ),
            )
          else
            ...pedidos.map(_tarjeta),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final id = (p['id'] as num).toInt();
    final items = (p['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final total = double.tryParse(p['total'].toString()) ?? 0;
    final estado = EstadoVenta.de(p['estado']?.toString());
    final esPendiente = p['estado'] == 'pendiente';
    final nombre = (p['cliente_nombre'] ?? p['cliente'] ?? 'Cliente').toString();
    final correo = p['cliente']?.toString();
    final telefono = p['cliente_telefono']?.toString();
    final nota = (p['nota'] ?? '').toString().trim();
    final marcando = _marcando.contains(id);

    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: estado.color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Pedido #$id',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: estado.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      estado.etiqueta,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: estado.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Spacer(),
                Text(
                  'Bs. ${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            // Cliente
            Wrap(
              spacing: 14,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _dato(Icons.person_outline, nombre, fuerte: true),
                if (telefono != null && telefono.isNotEmpty) _telefono(telefono),
                _dato(Icons.schedule, _fecha(p['fecha']?.toString())),
              ],
            ),
            if (correo != null && correo != nombre) ...[
              SizedBox(height: 2),
              Text(correo, style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            ],
            if (nota.isNotEmpty) ...[
              SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.sticky_note_2_outlined, size: 15, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        nota,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 10),
            Divider(color: AppColors.border, height: 1),
            SizedBox(height: 8),
            for (final it in items)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${it['cantidad']} x ${it['nombre']}',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    ),
                    Text(
                      'Bs. ${((double.tryParse(it['precio_unitario'].toString()) ?? 0) * (int.tryParse(it['cantidad'].toString()) ?? 0)).toStringAsFixed(2)}',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 10),
            if (esPendiente)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: marcando ? null : () => _marcarListo(p),
                  icon:
                      marcando
                          ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentOnAccent,
                            ),
                          )
                          : Icon(Icons.inventory_2_outlined, size: 17),
                  label: Text(marcando ? 'Marcando...' : 'Marcar como listo'),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 15, color: estado.color),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          p['cajero'] != null
                              ? 'Preparado por ${p['cajero']} · esperando al cliente'
                              : 'Esperando al cliente',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _avisarWhatsApp(p),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _verdeWhatsApp,
                      side: BorderSide(color: _verdeWhatsApp.withValues(alpha: 0.6)),
                    ),
                    icon: Icon(Icons.chat_outlined, size: 16),
                    label: Text('Avisar por WhatsApp'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _dato(IconData icono, String texto, {bool fuerte = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Flexible(
          child: Text(
            texto,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fuerte ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: fuerte ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _telefono(String telefono) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: telefono));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Telefono $telefono copiado')));
      },
      child: Tooltip(
        message: 'Copiar telefono',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
            SizedBox(width: 4),
            Text(telefono, style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            SizedBox(width: 4),
            Icon(Icons.copy_rounded, size: 12, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
