import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Producto agregado al carrito del cliente (catalogo en linea).
/// No confundir con CartItem, que es el carrito del cajero en el POS.
class ItemCarrito {
  final int productoId;
  String nombre;
  double precio;
  int stock;
  int cantidad;

  ItemCarrito({
    required this.productoId,
    required this.nombre,
    required this.precio,
    required this.stock,
    required this.cantidad,
  });

  double get subtotal => precio * cantidad;

  Map<String, dynamic> toJson() => {
        'producto_id': productoId,
        'nombre': nombre,
        'precio': precio,
        'stock': stock,
        'cantidad': cantidad,
      };

  factory ItemCarrito.fromJson(Map<String, dynamic> j) => ItemCarrito(
        productoId: (j['producto_id'] as num).toInt(),
        nombre: j['nombre'] as String,
        precio: (j['precio'] as num).toDouble(),
        stock: (j['stock'] as num).toInt(),
        cantidad: (j['cantidad'] as num).toInt(),
      );
}

/// Carrito del cliente. Singleton global: se mantiene al cambiar de pantalla
/// y al iniciar sesion, y se guarda en shared_preferences (en web,
/// localStorage) para sobrevivir a una recarga de la pagina.
/// Nunca permite mas unidades que el stock conocido del producto.
class CarritoCliente extends ChangeNotifier {
  CarritoCliente._();

  static final instance = CarritoCliente._();

  static const _clave = 'carrito_cliente';

  // Mapa con orden de insercion: el carrito se muestra en el orden agregado
  final Map<int, ItemCarrito> _items = {};

  List<ItemCarrito> get items => _items.values.toList();
  bool get vacio => _items.isEmpty;
  int get unidades => _items.values.fold(0, (s, i) => s + i.cantidad);
  double get total => _items.values.fold(0.0, (s, i) => s + i.subtotal);

  int cantidadDe(int productoId) => _items[productoId]?.cantidad ?? 0;

  /// Unidades que todavia se pueden agregar sin superar el stock.
  int restantePara(int productoId, int stock) =>
      max(0, stock - cantidadDe(productoId));

  /// Lee el carrito guardado. Llamar una vez en main() antes de runApp().
  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final texto = prefs.getString(_clave);
      if (texto == null) return;
      final lista = jsonDecode(texto) as List<dynamic>;
      _items.clear();
      for (final e in lista) {
        final item = ItemCarrito.fromJson(e as Map<String, dynamic>);
        if (item.cantidad > 0) _items[item.productoId] = item;
      }
      notifyListeners();
    } catch (_) {
      // Carrito guardado ilegible o sin almacenamiento: se empieza vacio
    }
  }

  /// Agrega [cantidad] unidades (sin superar el stock). Devuelve cuantas se
  /// agregaron realmente.
  int agregar({
    required int productoId,
    required String nombre,
    required double precio,
    required int stock,
    int cantidad = 1,
  }) {
    final actual = _items[productoId];
    final antes = actual?.cantidad ?? 0;
    final despues = min(stock, antes + cantidad);
    if (despues <= antes) return 0;
    if (actual == null) {
      _items[productoId] = ItemCarrito(
        productoId: productoId,
        nombre: nombre,
        precio: precio,
        stock: stock,
        cantidad: despues,
      );
    } else {
      actual
        ..nombre = nombre
        ..precio = precio
        ..stock = stock
        ..cantidad = despues;
    }
    _cambio();
    return despues - antes;
  }

  /// Cambia la cantidad (entre 1 y el stock).
  void cambiarCantidad(int productoId, int cantidad) {
    final item = _items[productoId];
    if (item == null) return;
    final nueva = min(max(cantidad, 1), max(1, item.stock));
    if (nueva == item.cantidad) return;
    item.cantidad = nueva;
    _cambio();
  }

  void quitar(int productoId) {
    if (_items.remove(productoId) != null) _cambio();
  }

  void vaciar() {
    if (_items.isEmpty) return;
    _items.clear();
    _cambio();
  }

  /// Actualiza nombre, precio y stock con el inventario actual
  /// (GET /inventario) y ajusta las cantidades. Devuelve avisos para el
  /// cliente cuando algo cambio.
  List<String> sincronizar(List<Map<String, dynamic>> inventario) {
    final porId = {for (final p in inventario) (p['id'] as num).toInt(): p};
    final avisos = <String>[];
    var hubo = false;

    for (final item in _items.values.toList()) {
      final p = porId[item.productoId];
      if (p == null) {
        _items.remove(item.productoId);
        avisos.add('${item.nombre} ya no esta disponible y se quito del carrito.');
        hubo = true;
        continue;
      }
      final stock = (p['stock'] as num).toInt();
      final precio = double.parse(p['precio'].toString());
      final nombre = p['nombre'] as String;
      if (stock <= 0) {
        _items.remove(item.productoId);
        avisos.add('$nombre se agoto y se quito del carrito.');
        hubo = true;
        continue;
      }
      if (item.cantidad > stock) {
        avisos.add('Solo quedan $stock de $nombre; se ajusto la cantidad.');
        item.cantidad = stock;
        hubo = true;
      }
      if ((precio - item.precio).abs() > 0.001) {
        avisos.add('El precio de $nombre cambio a Bs ${precio.toStringAsFixed(2)}.');
        hubo = true;
      }
      if (item.stock != stock || item.nombre != nombre) hubo = true;
      item
        ..stock = stock
        ..precio = precio
        ..nombre = nombre;
    }
    if (hubo) _cambio();
    return avisos;
  }

  void _cambio() {
    notifyListeners();
    _guardar();
  }

  Future<void> _guardar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _clave, jsonEncode(_items.values.map((i) => i.toJson()).toList()));
    } catch (_) {}
  }
}
