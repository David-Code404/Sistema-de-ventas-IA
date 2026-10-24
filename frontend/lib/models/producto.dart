class Producto {
  final int id;
  final String nombre;
  final double precio;
  final int? categoriaId;
  final String? categoriaNombre;
  final String claseModelo;
  final int stockMinimo;

  Producto({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.claseModelo,
    this.stockMinimo = 5,
  });

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      precio: double.parse(json['precio'].toString()),
      categoriaId: json['categoria_id'] as int?,
      categoriaNombre: json['categoria_nombre'] as String?,
      claseModelo: json['clase_modelo'] as String,
      stockMinimo: (json['stock_minimo'] as num?)?.toInt() ?? 5,
    );
  }
}