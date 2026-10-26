// Pruebas del carrito y del pedido del cliente (HU-18_980). El backend se
// simula con MockClient: no necesitan el servidor ni la base de datos.
// Ejecutar: cd frontend ; flutter test test/pedido_cliente_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/carrito_cliente.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/navegacion.dart';
import 'package:frontend/screens/carrito_cliente_screen.dart';
import 'package:frontend/screens/cliente_productos_screen.dart';
import 'package:frontend/screens/confirmar_pedido_screen.dart';
import 'package:frontend/screens/registro_cliente_screen.dart';
import 'package:frontend/theme/theme_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const api = 'http://api';
final botonPrincipal = find.byWidgetPredicate((w) => w is FilledButton).last;
var inventario = <Map<String, dynamic>>[];
final pedidosEnviados = <Map<String, dynamic>>[];
http.Response Function(http.Request)? respuestaPedido;

MockClient backend() => MockClient((req) async {
      final p = req.url.path;
      if (p == '/inventario') return http.Response(jsonEncode(inventario), 200);
      if (p == '/categorias') return http.Response('[]', 200);
      if (p.endsWith('/imagen')) return http.Response('', 404);
      if (p == '/pedidos') {
        pedidosEnviados.add(jsonDecode(req.body) as Map<String, dynamic>);
        await Future.delayed(const Duration(milliseconds: 300));
        return respuestaPedido!(req);
      }
      if (p == '/auth/registro') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        if (b['email'] == 'repetido@correo.com') {
          return http.Response(jsonEncode({'detail': 'Ese correo ya tiene una cuenta. Inicia sesion.'}), 409);
        }
        return http.Response(jsonEncode({
          'id': 9, 'username': b['email'], 'rol': 'cliente',
          'cliente': {'nombre': b['nombre'], 'telefono': b['telefono']},
        }), 201);
      }
      return http.Response('no', 404);
    });

Future<void> montar(WidgetTester t, Widget w, {double ancho = 360}) async {
  t.view.physicalSize = Size(ancho, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    Navegacion.login = () => const Text('PANTALLA LOGIN');
    Navegacion.inicioCliente = () => const Text('INICIO CLIENTE');
    SharedPreferences.setMockInitialValues({});
    CarritoCliente.instance.vaciar();
    pedidosEnviados.clear();
    inventario = [
      {'id': 1, 'nombre': 'Galletas', 'precio': '2.50', 'stock': 3, 'categoria_id': null, 'categoria_nombre': null},
      {'id': 2, 'nombre': 'Gaseosa', 'precio': '8.00', 'stock': 0, 'categoria_id': null, 'categoria_nombre': null},
    ];
    Session.iniciar(id: 9, u: 'ana@correo.com', r: 'cliente',
        datosCliente: {'nombre': 'Ana Perez', 'telefono': '70011223'});
  });

  for (final modo in [ThemeMode.dark, ThemeMode.light]) {
    for (final ancho in [360.0, 1280.0]) {
      testWidgets('catalogo: agotado, selector limitado al stock ($modo, $ancho)', (t) async {
        ThemeController.instance.value = modo;
        await http.runWithClient(() async {
          await montar(t, Scaffold(body: ClienteProductosScreen(apiBase: api)), ancho: ancho);
          // Gaseosa agotada: boton deshabilitado
          final agotado = t.widget<ButtonStyleButton>(find.ancestor(
              of: find.text('Agotado').last, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
          expect(agotado.onPressed, isNull);
          // Galletas: + hasta el maximo (3)
          for (var i = 0; i < 5; i++) {
            await t.tap(find.byTooltip('Agregar uno').first);
            await t.pump();
          }
          expect(find.text('3'), findsWidgets);
          await t.tap(find.text('Agregar al carrito'));
          await t.pump();
          expect(CarritoCliente.instance.unidades, 3);
          expect(find.text('Maximo en el carrito'), findsOneWidget);
          expect(find.text('3 en tu carrito'), findsOneWidget);
          expect(find.textContaining('Agregaste 3 x Galletas'), findsOneWidget);
          await t.pump(const Duration(seconds: 4));
        }, backend);
      });
    }
  }

  testWidgets('carrito: lista, total, quitar y vacio', (t) async {
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 3, cantidad: 2);
      await montar(t, CarritoClienteScreen(apiBase: api));
      expect(find.text('Bs 5.00'), findsWidgets);
      await t.tap(find.byTooltip('Agregar uno'));
      await t.pump();
      expect(CarritoCliente.instance.unidades, 3);
      expect(find.text('Maximo disponible'), findsOneWidget);
      await t.tap(find.byTooltip('Quitar del carrito'));
      await t.pumpAndSettle();
      expect(find.text('Tu carrito esta vacio'), findsOneWidget);
      expect(find.text('Volver al catalogo'), findsOneWidget);
    }, backend);
  });

  testWidgets('carrito: se ajusta si el stock bajo', (t) async {
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 10, cantidad: 5);
      await montar(t, CarritoClienteScreen(apiBase: api));
      expect(CarritoCliente.instance.cantidadDe(1), 3);
      expect(find.textContaining('Solo quedan 3 de Galletas'), findsOneWidget);
    }, backend);
  });

  testWidgets('confirmar: envia una sola vez, muestra numero y vacia el carrito', (t) async {
    respuestaPedido = (_) => http.Response(jsonEncode({
          'pedido_id': 26, 'estado': 'pendiente', 'total': 5.0, 'cliente_nombre': 'Ana Perez',
          'cliente_telefono': '70011223', 'nota': 'todo en 2 bolsas',
          'items': [{'producto_id': 1, 'nombre': 'Galletas', 'cantidad': 2, 'precio_unitario': 2.5, 'subtotal': 5.0}],
        }), 201);
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 3, cantidad: 2);
      await montar(t, ConfirmarPedidoScreen(apiBase: api));
      expect(find.widgetWithText(TextFormField, 'Ana Perez'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).last, 'todo en 2 bolsas');
      await t.ensureVisible(botonPrincipal);
      await t.tap(botonPrincipal);
      await t.pump();
      expect(find.text('Enviando pedido...'), findsOneWidget);
      await t.tap(find.text('Enviando pedido...'), warnIfMissed: false); // segundo toque
      await t.pumpAndSettle();
      expect(pedidosEnviados.length, 1);
      expect(pedidosEnviados.first['nota'], 'todo en 2 bolsas');
      expect(pedidosEnviados.first['cliente_telefono'], '70011223');
      expect(pedidosEnviados.first['items'], [{'producto_id': 1, 'cantidad': 2}]);
      expect(find.text('Pedido N° 26'), findsOneWidget);
      expect(CarritoCliente.instance.vacio, isTrue);
    }, backend);
  });

  testWidgets('confirmar: sin stock muestra el error y actualiza el carrito', (t) async {
    respuestaPedido = (_) => http.Response(
        jsonEncode({'detail': 'No hay stock suficiente de Galletas (quedan 3).'}), 422);
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 9, cantidad: 6);
      await montar(t, ConfirmarPedidoScreen(apiBase: api));
      await t.ensureVisible(botonPrincipal);
      await t.tap(botonPrincipal);
      await t.pumpAndSettle();
      expect(find.textContaining('No hay stock suficiente de Galletas'), findsOneWidget);
      expect(CarritoCliente.instance.cantidadDe(1), 3);
      expect(CarritoCliente.instance.vacio, isFalse);
    }, backend);
  });

  testWidgets('confirmar: sin conexion', (t) async {
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 3, cantidad: 1);
      await montar(t, ConfirmarPedidoScreen(apiBase: api));
      await t.ensureVisible(botonPrincipal);
      await t.tap(botonPrincipal);
      await t.pumpAndSettle();
      expect(find.textContaining('Sin conexion'), findsOneWidget);
    }, () => MockClient((_) async => throw http.ClientException('offline')));
  });

  testWidgets('confirmar: sesion no valida (401)', (t) async {
    respuestaPedido = (_) => http.Response(
        jsonEncode({'detail': 'Tu sesion no es valida. Vuelve a iniciar sesion.'}), 401);
    await http.runWithClient(() async {
      CarritoCliente.instance.agregar(productoId: 1, nombre: 'Galletas', precio: 2.5, stock: 3, cantidad: 1);
      await montar(t, ConfirmarPedidoScreen(apiBase: api));
      await t.ensureVisible(botonPrincipal);
      await t.tap(botonPrincipal);
      await t.pumpAndSettle();
      expect(find.textContaining('Tu sesion no es valida'), findsOneWidget);
      await t.tap(find.text('Iniciar sesion'));
      await t.pumpAndSettle();
      expect(find.text('PANTALLA LOGIN'), findsOneWidget);
    }, backend);
  });

  for (final ancho in [360.0, 1280.0]) {
    testWidgets('registro: valida campos y muestra error del servidor ($ancho)', (t) async {
      Session.cerrar();
      await http.runWithClient(() async {
        await montar(t, RegistroClienteScreen(apiBase: api), ancho: ancho);
        await t.ensureVisible(botonPrincipal);
        await t.tap(botonPrincipal);
        await t.pump();
        expect(find.text('Ingresa tu nombre'), findsOneWidget);
        expect(find.text('Correo no valido'), findsOneWidget);

        final campos = find.byType(TextFormField);
        await t.enterText(campos.at(0), 'Ana Perez');
        await t.enterText(campos.at(1), '7654321');
        await t.enterText(campos.at(2), 'repetido@correo.com');
        await t.enterText(campos.at(3), '70011223');
        await t.enterText(campos.at(5), 'secreto1');
        await t.enterText(campos.at(6), 'secreto1');
        await t.ensureVisible(botonPrincipal);
        await t.tap(botonPrincipal);
        await t.pumpAndSettle();
        expect(find.text('Ese correo ya tiene una cuenta. Inicia sesion.'), findsOneWidget);

        await t.enterText(campos.at(2), 'nueva@correo.com');
        await t.ensureVisible(botonPrincipal);
        await t.tap(botonPrincipal);
        await t.pumpAndSettle();
        expect(find.text('INICIO CLIENTE'), findsOneWidget);
        expect(Session.esCliente, isTrue);
        expect(Session.cliente?['telefono'], '70011223');
      }, backend);
    });
  }
}
