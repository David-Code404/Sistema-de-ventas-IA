class CartItem {
  final String id;
  final String name;
  final String imageAsset;
  final double price; // precio cobrado (con promocion si la hay)
  final double? originalPrice; // HU-26 1450: precio normal; null = sin promocion
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.imageAsset,
    required this.price,
    this.originalPrice,
    this.quantity = 1,
  });

  double get subtotal => price * quantity;

  /// HU-26 1450: true si este producto se cobra con descuento.
  bool get conPromocion => originalPrice != null && originalPrice! > price;

  /// HU-26 1450: porcentaje de descuento redondeado (0 si no hay).
  int get porcentajeDescuento =>
      conPromocion ? ((1 - price / originalPrice!) * 100).round() : 0;

  /// HU-26 1450: lo que el cliente se ahorra en esta linea.
  double get ahorro => conPromocion ? (originalPrice! - price) * quantity : 0;
}