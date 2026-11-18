/// HU-26 - Tarea 1420: estructura de la promocion.
///
/// Una promocion aplica un porcentaje de descuento a UN producto o a
/// TODA una categoria, entre una fecha de inicio y una de fin (incluidas).
/// Mismos campos y reglas que backend/modelo/promociones.py y la tabla
/// `promociones` (frontend/sql/migracion_hu26_1420_promociones.sql).
enum TipoPromocion { producto, categoria }

class Promocion {
  /// Limites del porcentaje: mayor que 0 y menor que 100.
  static const double porcentajeMinimo = 0.01;
  static const double porcentajeMaximo = 99.99;

  final int? id; // null mientras no se guarda
  final String nombre;
  final TipoPromocion tipo;
  final int? productoId; // solo si tipo == producto
  final int? categoriaId; // solo si tipo == categoria
  final double porcentaje; // 15 = 15 %
  final DateTime fechaInicio; // solo la fecha, incluida
  final DateTime fechaFin; // solo la fecha, incluida
  final bool activa;

  /// Opcionales: nombres que el backend puede enviar para mostrar en pantalla.
  final String? productoNombre;
  final String? categoriaNombre;

  Promocion({
    this.id,
    required this.nombre,
    required this.tipo,
    this.productoId,
    this.categoriaId,
    required this.porcentaje,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    this.activa = true,
    this.productoNombre,
    this.categoriaNombre,
  })  : fechaInicio = _soloFecha(fechaInicio),
        fechaFin = _soloFecha(fechaFin);

  factory Promocion.fromJson(Map<String, dynamic> json) {
    return Promocion(
      id: json['id'] as int?,
      nombre: (json['nombre'] ?? '') as String,
      tipo: json['tipo'] == 'categoria'
          ? TipoPromocion.categoria
          : TipoPromocion.producto,
      productoId: json['producto_id'] as int?,
      categoriaId: json['categoria_id'] as int?,
      porcentaje: double.parse(json['porcentaje'].toString()),
      fechaInicio: DateTime.parse(json['fecha_inicio'].toString()),
      fechaFin: DateTime.parse(json['fecha_fin'].toString()),
      activa: json['activa'] == true || json['activa'] == 1,
      productoNombre: json['producto_nombre'] as String?,
      categoriaNombre: json['categoria_nombre'] as String?,
    );
  }

  /// Formato que espera el backend (PromocionIn).
  Map<String, dynamic> toJson() => {
        'nombre': nombre.trim(),
        'tipo': tipo.name,
        'producto_id': tipo == TipoPromocion.producto ? productoId : null,
        'categoria_id': tipo == TipoPromocion.categoria ? categoriaId : null,
        'porcentaje': porcentaje,
        'fecha_inicio': _fechaApi(fechaInicio),
        'fecha_fin': _fechaApi(fechaFin),
        'activa': activa,
      };

  /// Nombre del producto o categoria al que se aplica, para mostrar.
  String get destino => tipo == TipoPromocion.producto
      ? (productoNombre ?? 'Producto #$productoId')
      : (categoriaNombre ?? 'Categoria #$categoriaId');

  /// True si esta activa y [dia] (hoy por defecto) cae entre sus fechas.
  bool vigenteEn([DateTime? dia]) {
    final d = _soloFecha(dia ?? DateTime.now());
    return activa && !d.isBefore(fechaInicio) && !d.isAfter(fechaFin);
  }

  /// True si ya paso la fecha de fin.
  bool vencidaEn([DateTime? dia]) =>
      _soloFecha(dia ?? DateTime.now()).isAfter(fechaFin);

  /// True si la promocion corresponde a ese producto (directo o por categoria).
  bool aplicaA({required int productoId, int? categoriaId}) =>
      tipo == TipoPromocion.producto
          ? this.productoId == productoId
          : categoriaId != null && this.categoriaId == categoriaId;

  /// Precio final con el descuento, redondeado a 2 decimales.
  double precioConDescuento(double precio) =>
      ((precio * (100 - porcentaje) / 100) * 100).round() / 100;

  /// Revisa las mismas reglas que el backend. Devuelve el mensaje de error
  /// o null si todo esta bien (util para los formularios de la 1430).
  String? validar() {
    final n = nombre.trim();
    if (n.length < 3) return 'El nombre debe tener al menos 3 caracteres.';
    if (n.length > 100) return 'El nombre no puede superar 100 caracteres.';
    if (tipo == TipoPromocion.producto && productoId == null) {
      return 'Elige el producto al que se aplica la promocion.';
    }
    if (tipo == TipoPromocion.categoria && categoriaId == null) {
      return 'Elige la categoria a la que se aplica la promocion.';
    }
    if (porcentaje < porcentajeMinimo || porcentaje > porcentajeMaximo) {
      return 'El descuento debe ser mayor que 0 y menor que 100.';
    }
    if (fechaFin.isBefore(fechaInicio)) {
      return 'La fecha de fin no puede ser anterior a la de inicio.';
    }
    return null;
  }

  static DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _fechaApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}