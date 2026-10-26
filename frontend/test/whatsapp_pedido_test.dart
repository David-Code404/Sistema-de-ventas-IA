// Pruebas del aviso por WhatsApp cuando el pedido esta listo (HU-18_1010).
// Ejecutar: cd frontend ; flutter test test/whatsapp_pedido_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/pedidos_monitor.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/models/whatsapp.dart';
import 'package:frontend/widgets/pedidos_panel.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const api = 'http://api';

Map<String, dynamic> pedido(int id, String estado, {String telefono = '70011223'}) => {
  'id': id,
  'estado': estado,
  'total': 7.5,
  'fecha': DateTime.now().toIso8601String(),
  'cliente': 'ana@correo.com',
  'cliente_nombre': 'Ana Perez',
  'cliente_telefono': telefono,
  'cajero': estado == 'listo' ? 'cajero' : null,
  'items': [
    {'nombre': 'Galletas', 'cantidad': 2, 'precio_unitario': 2.5},
    {'nombre': 'Gaseosa', 'cantidad': 1, 'precio_unitario': 2.5},
  ],
};

const mensajeEsperado =
    'Hola Ana, tu pedido #31\n'
    'Con el detalle:\n'
    '• 2 x Galletas\n'
    '• 1 x Gaseosa\n'
    'está listo para recoger.\n'
    'Total: Bs. 7.50\n'
    '¡Te esperamos!';

MockClient backend({
  required List<Map<String, dynamic>> pendientes,
  required List<Map<String, dynamic>> listos,
}) => MockClient((req) async {
  final p = req.url.path;
  if (p == '/pedidos/pendientes') return http.Response(jsonEncode(pendientes), 200);
  if (p == '/pedidos/listos') return http.Response(jsonEncode(listos), 200);
  if (p == '/pedidos/resumen') {
    return http.Response(
      jsonEncode({
        'pendientes': pendientes.length,
        'listos': listos.length,
        'sin_finalizar': pendientes.length + listos.length,
        'ultimo_pendiente_id': 0,
      }),
      200,
    );
  }
  if (p.endsWith('/listo')) {
    final ped = pendientes.removeAt(0);
    listos.add({...ped, 'estado': 'listo', 'cajero': 'cajero'});
    return http.Response(jsonEncode({'pedido_id': ped['id'], 'estado': 'listo'}), 200);
  }
  return http.Response('no', 404);
});

Future<void> montar(WidgetTester t, {double ancho = 1280}) async {
  t.view.physicalSize = Size(ancho, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: PedidosPanel(apiBase: api)));
  await t.pumpAndSettle();
}

Finder boton(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

void main() {
  final abiertos = <String>[];
  setUp(() {
    abiertos.clear();
    WhatsApp.abrir = abiertos.add;
    Session.iniciar(id: 2, u: 'cajero', r: 'cajero');
  });

  group('numero', () {
    test('celular boliviano sin prefijo', () {
      expect(WhatsApp.numero('70011223'), '59170011223');
      expect(WhatsApp.numero('6001-1223'), '59160011223');
      expect(WhatsApp.numero(' 700 11 223 '), '59170011223');
    });
    test('con prefijo', () {
      expect(WhatsApp.numero('+591 70011223'), '59170011223');
      expect(WhatsApp.numero('59170011223'), '59170011223');
      expect(WhatsApp.numero('+54 9 11 1234 5678'), '5491112345678');
    });
    test('no sirve para WhatsApp', () {
      expect(WhatsApp.numero('4123456'), isNull); // fijo
      expect(WhatsApp.numero('22123456'), isNull); // fijo de 8 digitos
      expect(WhatsApp.numero(''), isNull);
      expect(WhatsApp.numero(null), isNull);
    });
  });

  test('mensaje con el detalle del pedido', () {
    expect(WhatsApp.mensajePedidoListo(pedido(31, 'listo')), mensajeEsperado);
  });

  test('enlace wa.me con el mensaje codificado', () {
    final enlace = WhatsApp.enlacePedidoListo(pedido(31, 'listo'))!;
    expect(enlace, startsWith('https://wa.me/59170011223?text='));
    expect(Uri.parse(enlace).queryParameters['text'], mensajeEsperado);
    expect(WhatsApp.enlacePedidoListo(pedido(31, 'listo', telefono: '4123456')), isNull);
  });

  for (final ancho in [380.0, 1280.0]) {
    testWidgets('al marcar listo ofrece avisar por WhatsApp ($ancho)', (t) async {
      final pendientes = [pedido(31, 'pendiente')];
      await http.runWithClient(() async {
        await montar(t, ancho: ancho);
        await t.tap(boton('Marcar como listo'));
        await t.pumpAndSettle();
        await t.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text('Marcar como listo')),
        );
        await t.pumpAndSettle();

        expect(find.text('Pedido #31 listo para recoger'), findsOneWidget);
        expect(find.text(mensajeEsperado), findsOneWidget);
        await t.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text('Avisar por WhatsApp')),
        );
        await t.pumpAndSettle();
        expect(abiertos.single, startsWith('https://wa.me/59170011223?text='));
        expect(find.byType(AlertDialog), findsNothing);
        PedidosMonitor.instance.detener();
      }, () => backend(pendientes: pendientes, listos: []));
    });
  }

  testWidgets('"Ahora no" no abre WhatsApp', (t) async {
    final pendientes = [pedido(31, 'pendiente')];
    await http.runWithClient(() async {
      await montar(t);
      await t.tap(boton('Marcar como listo'));
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Marcar como listo')),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Ahora no'));
      await t.pumpAndSettle();
      expect(abiertos, isEmpty);
      PedidosMonitor.instance.detener();
    }, () => backend(pendientes: pendientes, listos: []));
  });

  testWidgets('boton en "Listos para recoger" abre WhatsApp', (t) async {
    await http.runWithClient(() async {
      await montar(t, ancho: 380);
      await t.tap(find.text('Listos para recoger (1)'));
      await t.pumpAndSettle();
      await t.tap(boton('Avisar por WhatsApp'));
      await t.pumpAndSettle();
      expect(abiertos.single, startsWith('https://wa.me/59170011223?text='));
    }, () => backend(pendientes: [], listos: [pedido(31, 'listo')]));
  });

  testWidgets('telefono fijo: explica y permite copiar el mensaje', (t) async {
    String? copiado;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.setData') copiado = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(
      () =>
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await http.runWithClient(() async {
      await montar(t);
      await t.tap(find.text('Listos para recoger (1)'));
      await t.pumpAndSettle();
      await t.tap(boton('Avisar por WhatsApp'));
      await t.pumpAndSettle();
      expect(abiertos, isEmpty);
      expect(find.textContaining('no sirve para WhatsApp'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Avisar por WhatsApp')),
        findsNothing,
      );
      await t.tap(find.text('Copiar mensaje'));
      await t.pumpAndSettle();
      expect(find.text('Mensaje copiado'), findsOneWidget);
      expect(copiado, contains('tu pedido #31'));
    }, () => backend(pendientes: [], listos: [pedido(31, 'listo', telefono: '4123456')]));
  });
}
