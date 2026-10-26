import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'models/carrito_cliente.dart';
import 'navegacion.dart';
import 'screens/cliente_shell.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.cargar();
  await CarritoCliente.instance.cargar();
  Navegacion.login = () => LoginScreen(apiBase: AppConfig.apiBase);
  Navegacion.inicioCliente = () => ClienteShell(apiBase: AppConfig.apiBase);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  static const String apiBase = AppConfig.apiBase;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'Caja Registradora Inteligente',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          home: LoginScreen(apiBase: apiBase),
        );
      },
    );
  }
}
