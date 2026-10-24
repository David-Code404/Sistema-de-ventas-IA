import 'package:flutter/material.dart';

/// Centra su contenido y lo limita a un ancho máximo. En una ventana de
/// escritorio ancha, sin esto los formularios y listas se estiran de borde
/// a borde y se ven desproporcionados; con esto quedan legibles como una
/// columna central, igual que cualquier formulario web bien hecho.
class BoundedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  BoundedContent({super.key, required this.child, this.maxWidth = 640});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
