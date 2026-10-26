import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controlador global de tema. Singleton accesible desde cualquier widget.
/// La eleccion se guarda en shared_preferences (en web, localStorage), asi
/// se mantiene al recargar la pagina o al volver a iniciar sesion.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.dark);

  static final instance = ThemeController._();

  static const _clave = 'modo_oscuro';

  bool get isDark => value == ThemeMode.dark;

  /// Lee el modo guardado. Llamar una vez en main() antes de runApp().
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final oscuro = prefs.getBool(_clave);
      if (oscuro != null) value = oscuro ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      // Sin almacenamiento disponible: se queda el modo oscuro por defecto
    }
  }

  void toggle() {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
    _guardar();
    _redibujarTodo();
  }

  /// AppColors son getters que leen [isDark]; los widgets ya construidos no
  /// se enteran del cambio por si solos. Se marcan todos para reconstruirse
  /// en el siguiente frame (conserva el estado: pantalla, formularios, etc.).
  static void _redibujarTodo() {
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(marcar);
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_clave, isDark);
    } catch (_) {}
  }
}
