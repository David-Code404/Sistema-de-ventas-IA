import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';

/// Icono de sol/luna para cambiar entre modo claro y oscuro, para las
/// pantallas sin sidebar (barra superior). Muestra el modo al que se
/// cambiara: sol en modo oscuro, luna en modo claro.
class BotonModoTema extends StatelessWidget {
  const BotonModoTema({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (_, mode, __) {
        final dark = mode == ThemeMode.dark;
        return IconButton(
          tooltip: dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
          onPressed: ThemeController.instance.toggle,
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
        );
      },
    );
  }
}
