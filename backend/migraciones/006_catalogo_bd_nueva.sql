-- Catalogo de la BD nueva: pone categorias y productos 1-26 tal cual (actualiza los que ya existen por id).
-- No toca usuarios, clientes, ventas ni 2FA.

INSERT INTO categorias (`id`, `nombre`, `descripcion`, `creado_en`, `color`) VALUES
(1, 'Papas fritas', 'Snacks de papa frita en bolsa', '2026-09-09 07:10:16', NULL),
(2, 'Snacks', 'Snacks salados que no son papa frita, ej. tipo cheetos', '2026-09-09 07:10:16', NULL),
(3, 'Condimentos', 'Salsas y condimentos para acompañar comidas', '2026-09-09 07:10:16', NULL),
(4, 'Cuidado personal', 'Productos de higiene y cuidado personal', '2026-09-09 07:10:16', NULL),
(6, 'Chocolates', '', '2026-11-22 00:27:20', '#FBBF24'),
(7, 'Gelatinas', '', '2026-11-22 00:27:45', '#38BDF8'),
(8, 'Gomitas', '', '2026-11-22 00:39:35', '#F472B6'),
(9, 'Belleza', '', '2026-11-22 16:30:12', '#F472B6'),
(10, 'Higiene', '', '2026-11-22 16:30:34', '#38BDF8'),
(11, 'Natural', '', '2026-11-22 16:31:15', '#34D399')
ON DUPLICATE KEY UPDATE `nombre`=VALUES(`nombre`), `descripcion`=VALUES(`descripcion`), `creado_en`=VALUES(`creado_en`), `color`=VALUES(`color`);

INSERT INTO productos (`id`, `nombre`, `precio`, `categoria_id`, `clase_modelo`, `activo`, `creado_en`, `actualizado_en`, `stock`) VALUES
(1, 'churrasco', 3.00, 2, 'churrasco', 0, '2026-10-03 20:12:56', '2026-11-22 00:25:26', 143),
(2, 'ta_bueno', 2.00, 1, 'ta_bueno', 0, '2026-10-03 20:14:29', '2026-11-22 00:25:24', 118),
(3, 'chizito', 2.00, 1, 'chizito', 0, '2026-10-03 20:20:28', '2026-11-22 00:25:15', 1),
(4, 'mostaza', 4.00, 3, 'mostaza', 0, '2026-10-03 20:21:38', '2026-10-04 02:59:45', 100),
(6, 'mostaza', 4.00, 3, 'mostaza_1791083124', 0, '2026-10-04 03:05:24', '2026-11-22 00:25:23', 118),
(7, 'chipchip', 2.00, 2, 'chipchip_1791204719', 0, '2026-10-05 12:51:59', '2026-11-22 00:25:17', 2),
(8, 'cocacola', 5.00, 2, 'cocacola_1791205074', 0, '2026-10-05 12:57:54', '2026-11-22 00:25:21', 27),
(9, 'Gomitas Miaw', 2.00, 8, 'gomitas_miaw_1795308119', 0, '2026-11-22 00:41:59', '2026-11-22 15:58:28', 10),
(10, 'Bon o Bon', 3.00, 6, 'bon_o_bon_1795308179', 0, '2026-11-22 00:42:59', '2026-11-22 15:58:30', 20),
(11, 'Pinzones Grageas', 4.00, 6, 'pinzones_grageas_1795308248', 0, '2026-11-22 00:44:08', '2026-11-22 15:58:33', 20),
(12, 'Chubi', 5.00, 6, 'chubi_1795308290', 0, '2026-11-22 00:44:50', '2026-11-22 15:58:31', 20),
(13, 'Happy Chocolate', 2.00, 6, 'happy_chocolate_1795308336', 0, '2026-11-22 00:45:36', '2026-11-22 15:58:34', 30),
(14, 'Gelatina Araña', 2.00, 7, 'gelatina_araña_1795308397', 0, '2026-11-22 00:46:37', '2026-11-22 01:38:20', 20),
(15, 'Chubi', 3.00, 6, 'chubi_1795363325', 1, '2026-11-22 16:02:05', '2026-11-22 16:02:05', 20),
(16, 'Gomitas Miaw', 2.00, 8, 'gomitas_miaw_1795364692', 1, '2026-11-22 16:24:52', '2026-11-22 16:24:52', 30),
(17, 'Bon o Bon', 3.00, 6, 'bon_o_bon_1795364769', 1, '2026-11-22 16:26:09', '2026-11-22 16:26:09', 20),
(18, 'Happy Chocolate', 2.00, 6, 'happy_chocolate_1795364864', 1, '2026-11-22 16:27:44', '2026-11-22 16:27:44', 20),
(19, 'Pinzones Grageas', 5.00, 6, 'pinzones_grageas_1795364944', 1, '2026-11-22 16:29:04', '2026-11-22 16:29:04', 20),
(20, 'Rulero', 1.00, 9, 'rulero_1795365178', 1, '2026-11-22 16:32:58', '2026-11-22 16:32:58', 50),
(21, 'Peine', 3.00, 9, 'peine_1795365296', 1, '2026-11-22 16:34:56', '2026-11-22 16:34:56', 30),
(22, 'Labial Colorina', 7.00, 9, 'labial_colorina_1795365392', 1, '2026-11-22 16:36:32', '2026-11-22 16:36:32', 10),
(23, 'Mentisan', 10.00, 11, 'mentisan_1795365516', 1, '2026-11-22 16:38:36', '2026-11-22 16:38:36', 20),
(24, 'Rasuradora', 2.00, 10, 'rasuradora_1795365623', 1, '2026-11-22 16:40:23', '2026-11-22 16:40:23', 50),
(25, 'Hilo Dental', 20.00, 10, 'hilo_dental_1795365737', 1, '2026-11-22 16:42:17', '2026-11-22 16:42:17', 20),
(26, 'Nivea', 15.00, 4, 'nivea_1795442835', 1, '2026-11-23 14:07:15', '2026-11-23 14:07:15', 20)
ON DUPLICATE KEY UPDATE `nombre`=VALUES(`nombre`), `precio`=VALUES(`precio`), `categoria_id`=VALUES(`categoria_id`), `clase_modelo`=VALUES(`clase_modelo`), `activo`=VALUES(`activo`), `creado_en`=VALUES(`creado_en`), `actualizado_en`=VALUES(`actualizado_en`), `stock`=VALUES(`stock`);
