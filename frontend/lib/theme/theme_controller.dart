import 'package:flutter/material.dart';

/// Controlador global de tema. Singleton accesible desde cualquier widget.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._() : super(ThemeMode.dark);

  static final instance = ThemeController._();

  bool get isDark => value == ThemeMode.dark;

  void toggle() {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
  }
}