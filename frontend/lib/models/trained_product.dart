import 'package:flutter/material.dart';

class TrainedProduct {
  final String name;
  final IconData icon;
  final Color color;

  final double price;

  TrainedProduct({
    required this.name,
    required this.icon,
    required this.color,
    this.price = 0.0,
  });
}

final trainedProducts = [
  TrainedProduct(name: 'Inca', icon: Icons.local_drink, color: Color(0xFFF5B800)),
  TrainedProduct(name: 'Galletas', icon: Icons.cookie, color: Color(0xFFD2691E)),
  TrainedProduct(name: 'Arroz', icon: Icons.rice_bowl, color: Color(0xFF64748B)),
  TrainedProduct(name: 'Leche', icon: Icons.coffee, color: Color(0xFF38BDF8)),
  TrainedProduct(name: 'Pan', icon: Icons.bakery_dining, color: Color(0xFF8B5E3C)),
  TrainedProduct(name: 'Chocolate', icon: Icons.icecream, color: Color(0xFFEF4444)),
];