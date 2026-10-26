import 'package:flutter/material.dart';

import '../models/carrito_cliente.dart';
import '../screens/carrito_cliente_screen.dart';
import '../theme/app_colors.dart';

/// Icono de carrito con el numero de unidades, para la barra superior del
/// cliente. Al tocarlo abre el carrito.
class BotonCarrito extends StatelessWidget {
  final String apiBase;

  const BotonCarrito({super.key, required this.apiBase});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CarritoCliente.instance,
      builder: (context, _) {
        final unidades = CarritoCliente.instance.unidades;
        return IconButton(
          tooltip: unidades == 0 ? 'Mi carrito' : 'Mi carrito ($unidades)',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CarritoClienteScreen(apiBase: apiBase))),
          icon: Badge(
            isLabelVisible: unidades > 0,
            backgroundColor: AppColors.accent,
            textColor: AppColors.accentOnAccent,
            label: Text(unidades > 99 ? '99+' : '$unidades',
                style: TextStyle(fontWeight: FontWeight.w700)),
            child: Icon(Icons.shopping_cart_outlined,
                size: 22, color: AppColors.textSecondary),
          ),
        );
      },
    );
  }
}

/// Miniatura de la imagen del producto (GET /productos/{id}/imagen), con un
/// icono si no tiene imagen.
class ImagenProducto extends StatelessWidget {
  final String apiBase;
  final int productoId;
  final double tamano;

  const ImagenProducto({
    super.key,
    required this.apiBase,
    required this.productoId,
    this.tamano = 56,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: tamano,
        height: tamano,
        color: AppColors.accent.withValues(alpha: 0.10),
        child: Image.network(
          '$apiBase/productos/$productoId/imagen',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.fastfood_outlined,
              color: AppColors.accent, size: tamano * 0.45),
        ),
      ),
    );
  }
}
