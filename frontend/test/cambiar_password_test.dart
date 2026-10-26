// Pruebas del cambio de contraseña confirmando la actual (HU-20_1090).
// El backend se simula con MockClient.
// Ejecutar: cd frontend ; flutter test test/cambiar_password_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/session.dart';
import 'package:frontend/widgets/cambiar_password_dialog.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const api = 'http://api';

final enviados = <Map<String, dynamic>>[];

MockClient backend() => MockClient((req) async {
  final b = jsonDecode(req.body) as Map<String, dynamic>;
  enviados.add(b);
  await Future.delayed(const Duration(milliseconds: 200));
  if (b['password_actual'] != 'vieja123') {
    return http.Response(
      jsonEncode({'detail': 'La contraseña actual es incorrecta.'}),
      401,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
  return http.Response(jsonEncode({'ok': true}), 200);
});

bool? resultado;

Future<void> abrir(WidgetTester t, {double ancho = 1280}) async {
  t.view.physicalSize = Size(ancho, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed:
                      () async => resultado = await mostrarCambiarPassword(context, apiBase: api),
                  child: const Text('abrir'),
                ),
              ),
        ),
      ),
    ),
  );
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

Future<void> llenar(WidgetTester t, String actual, String nueva, String confirmar) async {
  final campos = find.byType(TextFormField);
  await t.enterText(campos.at(0), actual);
  await t.enterText(campos.at(1), nueva);
  await t.enterText(campos.at(2), confirmar);
}

Future<void> guardar(WidgetTester t) async {
  await t.tap(find.text('Guardar'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    enviados.clear();
    resultado = null;
    Session.iniciar(id: 7, u: 'cajero', r: 'cajero');
  });

  for (final ancho in [360.0, 1280.0]) {
    testWidgets('cambio correcto: envia los datos, cierra y avisa ($ancho)', (t) async {
      await http.runWithClient(() async {
        await abrir(t, ancho: ancho);
        expect(find.text('Usuario: cajero'), findsOneWidget);
        await llenar(t, 'vieja123', 'nueva456', 'nueva456');
        await t.tap(find.text('Guardar'));
        await t.pump();
        // Mientras se envia, el boton queda deshabilitado (evita doble envio)
        final guardar = t.widget<FilledButton>(find.byType(FilledButton));
        expect(guardar.onPressed, isNull);
        await t.pumpAndSettle();

        expect(enviados.single, {
          'usuario_id': 7,
          'password_actual': 'vieja123',
          'password_nueva': 'nueva456',
        });
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Contraseña actualizada.'), findsOneWidget);
        expect(resultado, isTrue);
        // La sesion se mantiene
        expect(Session.usuarioId, 7);
      }, backend);
    });
  }

  testWidgets('contraseña actual incorrecta: mensaje bajo el campo y no cierra', (t) async {
    await http.runWithClient(() async {
      await abrir(t);
      await llenar(t, 'equivocada', 'nueva456', 'nueva456');
      await guardar(t);
      expect(find.text('La contraseña actual es incorrecta.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      // Al corregir la actual, el mensaje desaparece
      await t.enterText(find.byType(TextFormField).at(0), 'vieja123');
      await t.pump();
      await guardar(t);
      expect(find.byType(AlertDialog), findsNothing);
    }, backend);
  });

  testWidgets('validaciones antes de enviar', (t) async {
    await http.runWithClient(() async {
      await abrir(t);
      await guardar(t);
      expect(find.text('Ingresa tu contraseña actual'), findsOneWidget);

      await llenar(t, 'vieja123', '123', '123');
      await guardar(t);
      expect(find.text('Minimo 6 caracteres'), findsWidgets);

      await llenar(t, 'vieja123', 'vieja123', 'vieja123');
      await guardar(t);
      expect(find.text('Debe ser distinta de la actual'), findsOneWidget);

      await llenar(t, 'vieja123', 'nueva456', 'otra4567');
      await guardar(t);
      expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

      expect(enviados, isEmpty);
    }, backend);
  });

  testWidgets('sin conexion', (t) async {
    await http.runWithClient(() async {
      await abrir(t);
      await llenar(t, 'vieja123', 'nueva456', 'nueva456');
      await guardar(t);
      expect(find.textContaining('Sin conexion'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    }, () => MockClient((_) async => throw http.ClientException('offline')));
  });

  testWidgets('cancelar no envia nada', (t) async {
    await http.runWithClient(() async {
      await abrir(t);
      await llenar(t, 'vieja123', 'nueva456', 'nueva456');
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(enviados, isEmpty);
      expect(resultado, isFalse);
    }, backend);
  });
}
