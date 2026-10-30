import 'package:flutter/material.dart';
import 'theme_controller.dart';

/// Paleta de la app. Todo el color de la UI sale de aquí, para que
/// cualquier pantalla nueva quede visualmente consistente sin tener que
/// copiar códigos hex sueltos.
///
/// Los colores que cambian entre modos son GETTERS (no const).
/// En los widgets, quita 'const' de TextStyle / BoxDecoration / Divider
/// que los referencien — o ejecuta el sed del README de la tarea.
class AppColors {
  AppColors._();

  static bool get _dark => ThemeController.instance.isDark;

  // ── Fondos ──────────────────────────────────────────────────────────────
  static Color get background  => _dark ? Color(0xFF0B1220) : Color(0xFFF0F5FF);
  static Color get surface     => _dark ? Color(0xFF0F172A) : Color(0xFFFFFFFF);
  static Color get surfaceAlt  => _dark ? Color(0xFF16213A) : Color(0xFFF8FAFF);
  static Color get border      => _dark ? Color(0xFF1E293B) : Color(0xFFE2E8F0);
  static Color get borderStrong=> _dark ? Color(0xFF2A3B57) : Color(0xFFCBD5E1);

  // ── Texto ────────────────────────────────────────────────────────────────
  static Color get textPrimary   => _dark ? Colors.white              : Color(0xFF0B1220);
  static Color get textSecondary => _dark ? Colors.white70            : Color(0xFF475569);
  static Color get textMuted     => _dark ? Colors.white54            : Color(0xFF5B6B82);

  // ── Acento y semánticos ──────────────────────────────────────────────────
  // El verde accent funciona bien en ambos modos; se mantiene igual.
  // Verde de la marca: claro en modo oscuro y verde oscuro en modo claro, para que se
  // lea como texto sobre fondo blanco. accentOnAccent es el texto que va encima.
  static Color get accent         => _dark ? Color(0xFF34D399) : Color(0xFF047857);
  static Color get accentOnAccent => _dark ? Color(0xFF04241A) : Color(0xFFFFFFFF);

  static Color get danger   => _dark ? Color(0xFFF87171) : Color(0xFFB91C1C);
  static Color get onDanger => _dark ? Color(0xFF2A0A0A) : Color(0xFFFFFFFF);
  static Color get warning  => _dark ? Color(0xFFFBBF24) : Color(0xFFB45309);
  static Color get info     => _dark ? Color(0xFF38BDF8) : Color(0xFF0369A1);
  static Color get violeta  => _dark ? Color(0xFFA78BFA) : Color(0xFF6D28D9);

  // ── Paleta de etiquetas (fija — los mismos en ambos modos) ──────────────
  static const List<Color> tagPalette = [
    Color(0xFF34D399), // verde (acento de marca)
    Color(0xFF38BDF8), // celeste
    Color(0xFFA78BFA), // violeta
    Color(0xFFFB923C), // naranja
    Color(0xFFF472B6), // rosa
    Color(0xFFFBBF24), // ámbar
    Color(0xFF60A5FA), // azul
    Color(0xFF4ADE80), // verde lima
  ];

  static Color tagColorFor(int seed) =>
      tagPalette[seed.abs() % tagPalette.length];

  // ── Paleta para crear/editar categorías ─────────────────────────────────
  // Es getter porque referencia 'danger' y 'warning' que ahora son getters.
  static List<Color> get categoriaPalette => [
    accent,
    Color(0xFF38BDF8),
    Color(0xFFF472B6),
    warning,
    Color(0xFFA78BFA),
    danger,
  ];

  // ── Utilidades ───────────────────────────────────────────────────────────
  static String colorToHex(Color color) =>
      '#${color.value.toRadixString(16).substring(2).toUpperCase()}';

  static Color? hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final limpio = hex.replaceFirst('#', '');
    final valor  = int.tryParse(limpio, radix: 16);
    if (valor == null) return null;
    return Color(0xFF000000 | valor);
  }
}