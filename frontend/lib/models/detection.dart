/// Representa un producto detectado por el modelo de visión (YOLO).
///
/// El backend de detección entrega, por cada objeto reconocido, la clase
/// (nombre del producto) y una confianza. Es todo lo que el frontend necesita
/// para registrar la venta; el precio real llegará con el catálogo de
/// productos más adelante.
class Detection {
  final String className;
  final double confidence;

  Detection({
    required this.className,
    this.confidence = 1.0,
  });
}
