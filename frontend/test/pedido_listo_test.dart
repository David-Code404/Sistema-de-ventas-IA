// Pruebas de "marcar pedido como listo para recoger" (HU-18_1000): pantalla de
// pedidos del cajero, actualizacion automatica, contador y "Mis Pedidos" del
// cliente. El backend se simula con MockClient.
// Ejecutar: cd frontend ; flutter test test/pedido_listo_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/pedidos_monitor.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/screens/estado_pedido_screen.dart';
import 'package:frontend/widgets/pedidos_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const api = 'http://api';

Map<String, dynamic> pedido(int id, String estado, {String? nota, String? cajero}) => {
  'id': id,
  'estado': estado,
  'total': 7.5,
  'fecha': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
  'cliente': 'ana@correo.com',
  'cliente_nombre': 'Ana Perez',
  'cliente_telefono': '70011223',
  'nota': nota,
  'cajero': cajero,
  'items': [
    {'nombre': 'Galletas', 'cantidad': 3, 'precio_unitario': 2.5},
  ],
};

/// Backend simulado con estado: pedidos pendientes y listos.
class Backend {
  final pendientes = <Map<String, dynamic>>[];
  final listos = <Map<String, dynamic>>[];
  final marcados = <Map<String, dynamic>>[];
  http.Response? respuestaMarcar;

  MockClient cliente() => MockClient((req) async {
    final p = req.url.path;
    if (p == '/pedidos/pendientes') return http.Response(jsonEncode(pendientes), 200);
    if (p == '/pedidos/listos') return http.Response(jsonEncode(listos), 200);
    if (p == '/pedidos/resumen') {
      final ultimo =
          pendientes.isEmpty
              ? 0
              : pendientes.map((e) => e['id'] as int).reduce((a, b) => a > b ? a : b);
      return http.Response(
        jsonEncode({
          'pendientes': pendientes.length,
          'listos': listos.length,
          'sin_finalizar': pendientes.length + listos.length,
          'ultimo_pendiente_id': ultimo,
        }),
        200,
      );
    }
    final m = RegExp(r'^/pedidos/(\d+)/listo$').firstMatch(p);
    if (m != null) {
      marcados.add(jsonDecode(req.body) as Map<String, dynamic>);
      if (respuestaMarcar != null) return respuestaMarcar!;
      final id = int.parse(m.group(1)!);
      final ped = pendientes.firstWhere((e) => e['id'] == id);
      pendientes.remove(ped);
      listos.add({...ped, 'estado': 'listo', 'cajero': 'cajero'});
      return http.Response(jsonEncode({'pedido_id': id, 'estado': 'listo'}), 200);
    }
    return http.Response('no', 404);
  });
}

Future<void> montar(WidgetTester t, Widget w, {double ancho = 1280}) async {
  t.view.physicalSize = Size(ancho, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Finder boton(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

void main() {
  setUp(() => Session.iniciar(id: 2, u: 'cajero', r: 'cajero'));
  tearDown(() => PedidosMonitor.instance.detener());

  for (final ancho in [380.0, 1280.0]) {
    testWidgets('muestra datos del cliente y marca como listo ($ancho)', (t) async {
      final b = Backend()..pendientes.add(pedido(30, 'pendiente', nota: 'todo en 2 bolsas'));
      await http.runWithClient(() async {
        PedidosMonitor.instance.iniciar(api);
        await montar(t, PedidosPanel(apiBase: api), ancho: ancho);
        expect(PedidosMonitor.instance.pendientes, 1);
        expect(find.text('Pendientes (1)'), findsOneWidget);
        expect(find.text('Ana Perez'), findsOneWidget);
        expect(find.text('70011223'), findsOneWidget);
        expect(find.text('todo en 2 bolsas'), findsOneWidget);

        await t.tap(boton('Marcar como listo'));
        await t.pumpAndSettle();
        expect(find.text('Se descontara del inventario:'), findsOneWidget);
        expect(find.text('• 3 x Galletas'), findsOneWidget);
        await t.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text('Marcar como listo')),
        );
        await t.pumpAndSettle();

        // Despues de marcar se ofrece avisar por WhatsApp (HU-18_1010)
        expect(find.text('Pedido #30 listo para recoger'), findsOneWidget);
        await t.tap(find.text('Ahora no'));
        await t.pumpAndSettle();

        expect(b.marcados.single['usuario_id'], 2);
        expect(find.text('Pedido #30 listo para recoger. Stock descontado.'), findsOneWidget);
        expect(find.text('Pendientes (0)'), findsOneWidget);
        expect(find.text('Listos para recoger (1)'), findsOneWidget);
        // El contador del boton Pedidos baja en el momento (solo cuenta pendientes)
        expect(PedidosMonitor.instance.pendientes, 0);

        await t.tap(find.text('Listos para recoger (1)'));
        await t.pumpAndSettle();
        expect(find.textContaining('Preparado por cajero'), findsOneWidget);
        expect(boton('Marcar como listo'), findsNothing);
        PedidosMonitor.instance.detener();
      }, b.cliente);
    });
  }

  testWidgets('cancelar en la confirmacion no marca nada', (t) async {
    final b = Backend()..pendientes.add(pedido(30, 'pendiente'));
    await http.runWithClient(() async {
      await montar(t, PedidosPanel(apiBase: api));
      await t.tap(boton('Marcar como listo'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(b.marcados, isEmpty);
      expect(find.text('Pendientes (1)'), findsOneWidget);
      PedidosMonitor.instance.detener();
    }, b.cliente);
  });

  for (final caso in [
    (409, 'Este pedido ya fue marcado como listo.'),
    (422, 'No hay stock suficiente de: Galletas (pide 3, quedan 1).'),
  ]) {
    testWidgets('error ${caso.$1} muestra el mensaje del servidor', (t) async {
      final b =
          Backend()
            ..pendientes.add(pedido(30, 'pendiente'))
            ..respuestaMarcar = http.Response(jsonEncode({'detail': caso.$2}), caso.$1);
      await http.runWithClient(() async {
        await montar(t, PedidosPanel(apiBase: api));
        await t.tap(boton('Marcar como listo'));
        await t.pumpAndSettle();
        await t.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text('Marcar como listo')),
        );
        await t.pumpAndSettle();
        expect(find.text(caso.$2), findsOneWidget);
        PedidosMonitor.instance.detener();
      }, b.cliente);
    });
  }

  testWidgets('un pedido nuevo aparece solo, sin recargar, y sube el contador', (t) async {
    final b = Backend()..pendientes.add(pedido(30, 'pendiente'));
    await http.runWithClient(() async {
      PedidosMonitor.instance.iniciar(api);
      await montar(t, PedidosPanel(apiBase: api));
      expect(PedidosMonitor.instance.pendientes, 1);
      expect(find.text('Pedido #31'), findsNothing);

      // El cliente hace un pedido mientras el cajero tiene la pantalla abierta
      b.pendientes.add(pedido(31, 'pendiente'));
      await t.pump(PedidosMonitor.intervalo + const Duration(seconds: 1));
      await t.pumpAndSettle();

      expect(find.text('Pedido #31'), findsOneWidget);
      expect(find.text('Pendientes (2)'), findsOneWidget);
      expect(find.text('Llego un pedido nuevo (#31).'), findsOneWidget);
      expect(PedidosMonitor.instance.pendientes, 2);
      PedidosMonitor.instance.detener();
      PedidosMonitor.instance.detener();
    }, b.cliente);
  });

  testWidgets('el contador no corre para clientes', (t) async {
    Session.iniciar(id: 9, u: 'ana@correo.com', r: 'cliente');
    final b = Backend()..pendientes.add(pedido(30, 'pendiente'));
    await http.runWithClient(() async {
      PedidosMonitor.instance.iniciar(api);
      await t.pump(const Duration(seconds: 1));
      expect(PedidosMonitor.instance.pendientes, 0);
      PedidosMonitor.instance.detener();
    }, b.cliente);
  });

  testWidgets('Mis Pedidos del cliente: pendiente, listo y finalizada', (t) async {
    Session.iniciar(id: 9, u: 'ana@correo.com', r: 'cliente');
    final ventas = [
      {
        'id': 31,
        'estado': 'listo',
        'total': 5,
        'fecha': '2026-10-26T10:00:00',
        'metodo_pago': 'efectivo',
        'cantidad_productos': 2,
        'resumen_productos': '2x Galletas',
      },
      {
        'id': 30,
        'estado': 'pendiente',
        'total': 5,
        'fecha': '2026-10-26T09:00:00',
        'metodo_pago': 'efectivo',
        'cantidad_productos': 2,
        'resumen_productos': '2x Galletas',
      },
      {
        'id': 20,
        'estado': 'finalizada',
        'total': 5,
        'fecha': '2026-10-20T09:00:00',
        'metodo_pago': 'qr',
        'cantidad_productos': 2,
        'resumen_productos': '2x Galletas',
      },
    ];
    await http.runWithClient(() async {
      await montar(t, Scaffold(body: EstadoPedidoScreen(apiBase: api)), ancho: 380);
      expect(find.text('PEDIDOS ACTUALES'), findsOneWidget);
      expect(find.text('Listo para recoger'), findsOneWidget);
      expect(find.text('¡Tu pedido esta listo! Pasa a recogerlo a la tienda.'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Finalizada'), findsOneWidget);
      // Antes, un pedido pendiente aparecia como "Finalizado" con "Pago en efectivo"
      expect(find.text('Pago en efectivo'), findsNothing);
      expect(find.text('Pago por QR'), findsOneWidget);
      await t.pumpWidget(const SizedBox()); // cancela la actualizacion automatica
    }, () => MockClient((_) async => http.Response(jsonEncode(ventas), 200)));
  });
}
