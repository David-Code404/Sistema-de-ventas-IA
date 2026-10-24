import 'package:flutter/material.dart';
import '../models/cart_item.dart';
import '../theme/app_colors.dart';
import 'cart_item_tile.dart';

class CartPanel extends StatelessWidget {
  final List<CartItem> items;
  final void Function(CartItem) onIncrementItem;
  final void Function(CartItem) onDecrementItem;
  final void Function(CartItem) onRemoveItem;
  final VoidCallback onRegistrarVenta;
  final double total;
  final int totalProducts;
  final VoidCallback onManageCategorias;
  final VoidCallback onViewCatalogo;
  final VoidCallback onViewVentas;

  CartPanel({
    super.key,
    required this.items,
    required this.onIncrementItem,
    required this.onDecrementItem,
    required this.onRemoveItem,
    required this.onRegistrarVenta,
    required this.total,
    required this.totalProducts,
    required this.onManageCategorias,
    required this.onViewCatalogo,
    required this.onViewVentas,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewVentas,
                  icon: Icon(Icons.receipt_long_outlined, size: 15, color: AppColors.textSecondary),
                  label: Text('Ventas', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.border.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewCatalogo,
                  icon: Icon(Icons.search, size: 15, color: AppColors.textSecondary),
                  label: Text('Catálogo', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.border),
                    backgroundColor: AppColors.border.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onManageCategorias,
              icon: Icon(Icons.category_outlined, size: 15, color: AppColors.textSecondary),
              label: Text(
                'Gestionar categorías',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.border),
                backgroundColor: AppColors.border.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(height: 12),

          Row(
            children: [
              Icon(Icons.shopping_cart, color: AppColors.textSecondary, size: 16),
              SizedBox(width: 8),
              Text(
                'CARRITO',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
              ),
              Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalProducts items',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'El carrito está vacío.\nMuestra un producto a la cámara para agregarlo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(color: AppColors.border),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return CartItemTile(
                        item: item,
                        onIncrement: () => onIncrementItem(item),
                        onDecrement: () => onDecrementItem(item),
                        onRemove: () => onRemoveItem(item),
                      );
                    },
                  ),
          ),
          Divider(color: AppColors.border),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL COMPRA', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              Text('$totalProducts productos', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'S/ ${total.toStringAsFixed(2)}',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 30, fontWeight: FontWeight.bold),
          ),

          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: items.isEmpty ? null : onRegistrarVenta,
              icon: Icon(Icons.check_circle_outline),
              label: Text('REGISTRAR VENTA'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}