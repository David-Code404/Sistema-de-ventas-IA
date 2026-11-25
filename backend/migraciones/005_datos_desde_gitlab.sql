-- ============================================================
-- Datos de la BD de GitLab que faltan en la version web (GitHub / Render / Aiven)
-- SOLO AGREGA lo que no existe (INSERT IGNORE): no borra ni cambia nada de lo que ya hay.
-- NO incluye: verificacion en dos pasos, usuarios, clientes ni ventas.
-- Productos: 17 (ids 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18) · Proveedores: 3 · Compras: 4 · Promociones: 1
-- Las imagenes de los productos NO van en la base: son los archivos backend/modelo/imagenes_productos/<id>.jpg
-- ============================================================

INSERT IGNORE INTO proveedores (id, razon_social, nit, telefono, correo, direccion, activo, creado_en) VALUES
  (1, 'Distribuidora Andina S.R.L.', '1020304050', '70011223', 'ventas@andina.bo', 'Av. Blanco Galindo km 4', 1, '2026-11-18 08:26:42'),
  (2, 'Embol S.A.', '1007039026', '44260000', 'pedidos@embol.bo', 'Av. Petrolera km 6', 1, '2026-11-18 08:26:42'),
  (3, 'Proveedor sin compras', '9988776655', '70099887', NULL, NULL, 1, '2026-11-18 08:26:42');

INSERT IGNORE INTO productos (id, nombre, precio, categoria_id, clase_modelo, activo, creado_en, actualizado_en, stock) VALUES
  (1, 'churrasco', 3.00, 2, 'churrasco', 1, '2026-10-04 00:12:56', '2026-10-05 04:48:58', 143),
  (2, 'ta_bueno', 2.00, 1, 'ta_bueno', 1, '2026-10-04 00:14:29', '2026-11-22 16:29:36', 118),
  (3, 'chizito', 2.00, 1, 'chizito', 1, '2026-10-04 00:20:28', '2026-11-22 16:29:36', 1),
  (4, 'mostaza', 4.00, 3, 'mostaza', 0, '2026-10-04 00:21:38', '2026-10-04 06:59:45', 100),
  (6, 'mostaza', 4.00, 3, 'mostaza_1791083124', 1, '2026-10-04 07:05:24', '2026-10-05 04:29:24', 118),
  (7, 'chipchip', 2.00, 2, 'chipchip_1791204719', 1, '2026-10-05 16:51:59', '2026-11-22 16:19:42', 2),
  (8, 'cocacola', 5.00, 2, 'cocacola_1791205074', 0, '2026-10-05 16:57:54', '2026-11-20 04:00:47', 27),
  (9, 'Artesanas', 1.00, 2, 'artesanas_1795007410', 1, '2026-11-18 13:10:10', '2026-11-22 16:19:32', 100),
  (10, 'Big shark', 2.00, 2, 'big_shark_1795008543', 1, '2026-11-18 13:29:03', '2026-11-22 16:19:32', 100),
  (11, 'Bon o Bon', 2.00, 2, 'bon_o_bon_1795008659', 1, '2026-11-18 13:30:59', '2026-11-22 16:19:32', 100),
  (12, 'Cereal', 1.50, 2, 'cereal_1795008729', 1, '2026-11-18 13:32:09', '2026-11-22 16:19:42', 100),
  (13, 'Chocolitas', 1.50, 2, 'chocolitas_1795008789', 1, '2026-11-18 13:33:09', '2026-11-22 16:19:42', 100),
  (14, 'Galleta de agua', 1.50, 2, 'galleta_de_agua_1795008830', 1, '2026-11-18 13:33:50', '2026-11-18 13:33:50', 100),
  (15, 'Gelatina', 1.50, 2, 'gelatina_1795008965', 1, '2026-11-18 13:36:05', '2026-11-18 13:36:05', 100),
  (16, 'Genio', 3.00, 2, 'genio_1795009086', 1, '2026-11-18 13:38:06', '2026-11-18 13:38:06', 100),
  (17, 'Gomutcho', 1.50, 2, 'gomutcho_1795009158', 1, '2026-11-18 13:39:18', '2026-11-18 13:39:18', 100),
  (18, 'Tita', 1.00, 2, 'tita_1795009363', 1, '2026-11-18 13:42:43', '2026-11-18 13:42:43', 100);

INSERT IGNORE INTO compras (id, proveedor_id, fecha, numero_factura, total, nota, usuario_id, creado_en) VALUES
  (1, 1, '2026-08-10', NULL, 60.00, NULL, 1, '2026-08-10 17:15:00'),
  (2, 1, '2026-10-20', NULL, 37.60, NULL, 1, '2026-10-20 18:30:00'),
  (3, 1, '2026-11-15', NULL, 97.30, NULL, 1, '2026-11-16 00:45:00'),
  (4, 2, '2026-11-12', NULL, 168.00, NULL, 1, '2026-11-12 19:00:00');

INSERT IGNORE INTO detalle_compra (id, compra_id, producto_id, cantidad, costo_unitario) VALUES
  (1, 1, 2, 24, 1.20),
  (2, 1, 3, 24, 1.30),
  (3, 2, 3, 12, 1.30),
  (4, 2, 7, 20, 1.10),
  (5, 3, 2, 36, 1.25),
  (6, 3, 3, 18, 1.35),
  (7, 3, 6, 10, 2.80),
  (8, 4, 8, 48, 3.50);

INSERT IGNORE INTO promociones (id, nombre, tipo, producto_id, categoria_id, porcentaje, fecha_inicio, fecha_fin, activa, desactivada_auto_en, creado_en, actualizado_en) VALUES
  (2, 'Mitad de descuento PAPAS', 'producto', 2, NULL, 50.00, '2026-11-18', '2026-11-22', 1, NULL, '2026-11-18 09:30:01', '2026-11-18 10:28:59');

