class Categoria {
  final int id;
  final String nombre;
  final String descripcion;
  final String? color;

  Categoria({required this.id, required this.nombre, required this.descripcion, this.color});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      descripcion: (json['descripcion'] ?? '') as String,
      color: json['color'] as String?,
    );
  }
}