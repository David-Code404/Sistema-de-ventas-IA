class CartItem {
  final String id;
  final String name;
  final String imageAsset;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.imageAsset,
    required this.price,
    this.quantity = 1,
  });

  double get subtotal => price * quantity;
}