// Pruebas de la alerta visual de stock bajo (StockBajoBanner) al reducir el
// stock hasta el minimo configurado (HU-21_1150). El backend se simula con
// MockClient: el test cambia el stock "en el servidor" y verifica que la
// alerta de la pantalla de venta se actualiza sola en el siguiente sondeo.
// Ejecutar: cd frontend ; flutter test test/stock_bajo_banner_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/theme/theme_controller.dart';
import 'package:frontend/widgets/stock_bajo_banner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const api = 'http://api';
const cadaCuanto = Duration(seconds: 10);

/// Inventario simulado: GET /inventario/stock-bajo devuelve stock <= minimo.
class Servidor {
  final productos = <Map<String, dynamic>>[
    {'id': 1, 'nombre': 'Galletas', 'stock': 10, 'stock_minimo': 5, 'categoria_nombre': 'Snacks'},
  ];

  void stock(int id, int valor) => productos.firstWhere((p) => p['id'] == id)['stock'] = valor;

  http.Response respuesta(http.Request req) {
    if (req.url.path != '/inventario/stock-bajo') return http.Response('no', 404);
    final bajos =
        productos.where((p) => (p['stock'] as int) <= (p['stock_minimo'] as int)).toList()
          ..sort((a, b) => (a['stock'] as int).compareTo(b['stock'] as int));
    return http.Response(jsonEncode(bajos), 200);
  }

  MockClient cliente() => MockClient((req) async => respuesta(req));
}

Future<void> montar(WidgetTester t, {double ancho = 1280}) async {
  t.view.physicalSize = Size(ancho, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    const MaterialApp(home: Scaffold(body: Column(children: [StockBajoBanner(apiBase: api)]))),
  );
  await t.pumpAndSettle();
}

/// Avanza al siguiente sondeo del banner.
Future<void> siguienteSondeo(WidgetTester t) async {
  await t.pump(cadaCuanto);
  await t.pumpAndSettle();
}

Finder get banner => find.textContaining('Alerta de stock');

void main() {
  for (final modo in [ThemeMode.dark, ThemeMode.light]) {
    for (final ancho in [360.0, 1280.0]) {
      testWidgets('reducir hasta el minimo muestra la alerta sin recargar ($modo, $ancho)', (
        t,
      ) async {
        ThemeController.instance.value = modo;
        final s = Servidor();
        await http.runWithClient(() async {
          await montar(t, ancho: ancho);
          expect(banner, findsNothing, reason: 'stock 10 > minimo 5');

          s.stock(1, 6); // minimo + 1
          await siguienteSondeo(t);
          expect(banner, findsNothing, reason: 'stock 6 > minimo 5');

          s.stock(1, 5); // = minimo
          await siguienteSondeo(t);
          expect(find.text('Alerta de stock: 1 con stock bajo'), findsOneWidget);

          await t.tap(find.text('Ver detalle'));
          await t.pumpAndSettle();
          expect(find.text('Galletas'), findsOneWidget);
          expect(find.text('Quedan 5 · mínimo 5'), findsOneWidget);

          s.stock(1, 0); // agotado
          await siguienteSondeo(t);
          expect(find.text('Alerta de stock: 1 producto agotado'), findsOneWidget);
          expect(find.text('Agotado'), findsOneWidget);

          s.stock(1, 10); // repuesto
          await siguienteSondeo(t);
          expect(banner, findsNothing, reason: 'al reponer la alerta desaparece');

          await t.pumpWidget(const SizedBox()); // detiene el sondeo
        }, s.cliente);
      });
    }
  }

  testWidgets('la alerta aparece en el siguiente sondeo, no antes', (t) async {
    final s = Servidor();
    await http.runWithClient(() async {
      await montar(t);
      s.stock(1, 5);
      await t.pump(cadaCuanto - const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(banner, findsNothing, reason: 'todavia no toco consultar');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(banner, findsOneWidget, reason: 'a los 10 s ya aparece');
      await t.pumpWidget(const SizedBox());
    }, s.cliente);
  });

  testWidgets('descartar oculta la alerta hasta que el stock vuelve a cambiar', (t) async {
    final s = Servidor()..stock(1, 5);
    await http.runWithClient(() async {
      await montar(t);
      expect(banner, findsOneWidget);
      await t.tap(find.byTooltip('Descartar hasta que cambie el stock'));
      await t.pumpAndSettle();
      expect(banner, findsNothing);

      await siguienteSondeo(t); // mismo stock: sigue oculta
      expect(banner, findsNothing);

      s.stock(1, 4); // el stock baja otra vez: vuelve a avisar
      await siguienteSondeo(t);
      expect(banner, findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }, s.cliente);
  });

  testWidgets('varios productos: agotados y con stock bajo a la vez', (t) async {
    final s =
        Servidor()
          ..productos.add({
            'id': 2,
            'nombre': 'Gaseosa',
            'stock': 0,
            'stock_minimo': 3,
            'categoria_nombre': null,
          })
          ..stock(1, 4);
    await http.runWithClient(() async {
      await montar(t);
      expect(find.text('Alerta de stock: 1 producto agotado · 1 con stock bajo'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }, s.cliente);
  });

  testWidgets('si el servidor falla, conserva la ultima alerta', (t) async {
    final s = Servidor()..stock(1, 5);
    var caido = false;
    await http.runWithClient(
      () async {
        await montar(t);
        expect(banner, findsOneWidget);
        caido = true;
        await siguienteSondeo(t);
        expect(banner, findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
      () => MockClient((req) async {
        if (caido) throw http.ClientException('sin conexion');
        return s.respuesta(req);
      }),
    );
  });
}
