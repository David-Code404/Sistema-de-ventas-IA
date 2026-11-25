-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 25-11-2026 a las 13:24:20
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `caja_registradora_ia`
--

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `categorias`
--

CREATE TABLE `categorias` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `descripcion` varchar(255) DEFAULT NULL,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `color` varchar(7) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `categorias`
--

INSERT INTO `categorias` (`id`, `nombre`, `descripcion`, `creado_en`, `color`) VALUES
(1, 'Papas fritas', 'Snacks de papa frita en bolsa', '2026-09-09 07:10:16', NULL),
(2, 'Snacks', 'Snacks salados que no son papa frita, ej. tipo cheetos', '2026-09-09 07:10:16', NULL),
(3, 'Condimentos', 'Salsas y condimentos para acompañar comidas', '2026-09-09 07:10:16', NULL),
(4, 'Cuidado personal', 'Productos de higiene y cuidado personal', '2026-09-09 07:10:16', NULL),
(6, 'Chocolates', '', '2026-11-22 00:27:20', '#FBBF24'),
(7, 'Gelatinas', '', '2026-11-22 00:27:45', '#38BDF8'),
(8, 'Gomitas', '', '2026-11-22 00:39:35', '#F472B6'),
(9, 'Belleza', '', '2026-11-22 16:30:12', '#F472B6'),
(10, 'Higiene', '', '2026-11-22 16:30:34', '#38BDF8'),
(11, 'Natural', '', '2026-11-22 16:31:15', '#34D399');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `clientes`
--

CREATE TABLE `clientes` (
  `id` int(11) NOT NULL,
  `documento` varchar(25) NOT NULL,
  `tipo_documento` varchar(20) NOT NULL DEFAULT 'CI',
  `nombre` varchar(100) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `direccion` varchar(150) DEFAULT NULL,
  `total_compras` int(11) NOT NULL DEFAULT 1,
  `creado_en` datetime NOT NULL DEFAULT current_timestamp(),
  `actualizado_en` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `usuario_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `clientes`
--

INSERT INTO `clientes` (`id`, `documento`, `tipo_documento`, `nombre`, `email`, `telefono`, `direccion`, `total_compras`, `creado_en`, `actualizado_en`, `usuario_id`) VALUES
(1, '10325319', 'CI', 'wilder', 'wildercrk@gmail.com', '645243', 'calle', 2, '2026-10-25 21:11:26', '2026-10-25 21:54:28', NULL),
(3, '10304050', 'CI', 'jose Duran', 'jose@gmail.com', '123456789', 'millares', 3, '2026-10-25 21:58:44', '2026-10-25 23:00:22', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `compras`
--

CREATE TABLE `compras` (
  `id` int(11) NOT NULL,
  `proveedor_id` int(11) NOT NULL,
  `usuario_id` int(11) DEFAULT NULL,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `compras`
--

INSERT INTO `compras` (`id`, `proveedor_id`, `usuario_id`, `creado_en`) VALUES
(1, 1, 1, '2026-08-10 13:15:00'),
(2, 1, 1, '2026-10-20 14:30:00'),
(3, 1, 1, '2026-11-15 20:45:00'),
(4, 2, 1, '2026-11-12 15:00:00');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_compra`
--

CREATE TABLE `detalle_compra` (
  `id` int(11) NOT NULL,
  `compra_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL CHECK (`cantidad` > 0),
  `costo_unitario` decimal(10,2) NOT NULL CHECK (`costo_unitario` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `detalle_compra`
--

INSERT INTO `detalle_compra` (`id`, `compra_id`, `producto_id`, `cantidad`, `costo_unitario`) VALUES
(1, 1, 2, 24, 1.20),
(2, 1, 3, 24, 1.30),
(3, 2, 3, 12, 1.30),
(4, 2, 7, 20, 1.10),
(5, 3, 2, 36, 1.25),
(6, 3, 3, 18, 1.35),
(7, 3, 6, 10, 2.80),
(8, 4, 8, 48, 3.50);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_venta`
--

CREATE TABLE `detalle_venta` (
  `id` int(11) NOT NULL,
  `venta_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL DEFAULT 1,
  `precio_unitario` decimal(10,2) NOT NULL,
  `precio_original` decimal(10,2) DEFAULT NULL,
  `promocion_id` int(11) DEFAULT NULL,
  `subtotal` decimal(10,2) GENERATED ALWAYS AS (`cantidad` * `precio_unitario`) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `detalle_venta`
--

INSERT INTO `detalle_venta` (`id`, `venta_id`, `producto_id`, `cantidad`, `precio_unitario`, `precio_original`, `promocion_id`) VALUES
(1, 2, 4, 1, 4.00, NULL, NULL),
(4, 10, 2, 1, 2.00, NULL, NULL),
(13, 18, 2, 1, 2.00, NULL, NULL),
(16, 19, 3, 2, 2.00, NULL, NULL),
(18, 19, 2, 1, 2.00, NULL, NULL),
(19, 20, 8, 7, 5.00, NULL, NULL),
(20, 20, 2, 4, 2.00, NULL, NULL),
(21, 20, 6, 4, 4.00, NULL, NULL),
(23, 20, 7, 2, 2.00, NULL, NULL),
(36, 22, 3, 2, 2.00, NULL, NULL),
(38, 23, 3, 2, 2.00, NULL, NULL),
(40, 24, 3, 2, 2.00, NULL, NULL),
(42, 25, 3, 2, 2.00, NULL, NULL),
(44, 26, 3, 2, 2.00, NULL, NULL),
(46, 26, 2, 1, 2.00, NULL, NULL),
(47, 27, 3, 2, 2.00, NULL, NULL),
(49, 28, 3, 1, 2.00, NULL, NULL),
(50, 29, 3, 2, 2.00, NULL, NULL),
(52, 30, 3, 2, 2.00, NULL, NULL),
(54, 31, 3, 1, 2.00, NULL, NULL),
(55, 32, 3, 3, 2.00, NULL, NULL),
(56, 33, 7, 2, 2.00, NULL, NULL),
(57, 34, 7, 2, 2.00, NULL, NULL),
(58, 35, 7, 1, 2.00, NULL, NULL),
(59, 35, 3, 2, 2.00, NULL, NULL),
(60, 36, 7, 3, 2.00, NULL, NULL),
(61, 37, 7, 1, 2.00, NULL, NULL),
(62, 38, 7, 1, 2.00, NULL, NULL),
(63, 39, 3, 1, 2.00, NULL, NULL),
(64, 40, 7, 1, 2.00, NULL, NULL),
(65, 41, 7, 1, 2.00, NULL, NULL),
(66, 42, 3, 1, 2.00, NULL, NULL),
(67, 43, 3, 2, 2.00, NULL, NULL),
(68, 43, 8, 1, 5.00, NULL, NULL),
(69, 44, 8, 1, 5.00, NULL, NULL),
(70, 45, 8, 1, 5.00, NULL, NULL),
(71, 46, 8, 1, 5.00, NULL, NULL),
(72, 47, 8, 2, 5.00, NULL, NULL),
(73, 48, 8, 2, 5.00, NULL, NULL),
(74, 49, 8, 1, 5.00, NULL, NULL),
(75, 51, 2, 1, 1.00, 2.00, 2),
(137, 54, 11, 2, 4.00, NULL, NULL),
(138, 54, 10, 1, 3.00, NULL, NULL),
(146, 56, 10, 2, 3.00, NULL, NULL),
(147, 56, 12, 1, 5.00, NULL, NULL),
(148, 56, 13, 1, 2.00, NULL, NULL),
(150, 56, 9, 2, 2.00, NULL, NULL),
(157, 60, 10, 2, 3.00, NULL, NULL),
(159, 60, 12, 2, 5.00, NULL, NULL),
(161, 64, 10, 2, 3.00, NULL, NULL),
(162, 64, 9, 2, 2.00, NULL, NULL),
(169, 66, 10, 2, 3.00, NULL, NULL),
(171, 66, 11, 2, 4.00, NULL, NULL),
(173, 66, 12, 1, 5.00, NULL, NULL),
(174, 66, 9, 1, 2.00, NULL, NULL),
(175, 66, 13, 1, 2.00, NULL, NULL),
(245, 67, 10, 3, 3.00, NULL, NULL),
(246, 67, 13, 1, 2.00, NULL, NULL),
(250, 67, 12, 1, 5.00, NULL, NULL),
(377, 69, 10, 1, 3.00, NULL, NULL),
(385, 70, 15, 1, 3.00, NULL, NULL),
(386, 70, 23, 2, 10.00, NULL, NULL),
(387, 70, 17, 1, 3.00, NULL, NULL),
(388, 70, 18, 1, 2.00, NULL, NULL),
(391, 70, 19, 1, 5.00, NULL, NULL),
(393, 70, 22, 5, 7.00, NULL, NULL),
(395, 70, 21, 2, 3.00, NULL, NULL),
(396, 70, 24, 1, 2.00, NULL, NULL),
(397, 70, 16, 2, 2.00, NULL, NULL),
(398, 70, 20, 1, 1.00, NULL, NULL),
(399, 70, 25, 1, 20.00, NULL, NULL),
(487, 73, 22, 1, 7.00, NULL, NULL),
(507, 74, 23, 1, 10.00, NULL, NULL),
(586, 79, 25, 1, 20.00, NULL, NULL),
(587, 79, 20, 1, 1.00, NULL, NULL),
(588, 79, 23, 1, 10.00, NULL, NULL),
(589, 79, 24, 1, 2.00, NULL, NULL),
(590, 79, 17, 1, 3.00, NULL, NULL),
(601, 81, 17, 1, 3.00, NULL, NULL),
(602, 81, 20, 1, 1.00, NULL, NULL),
(603, 81, 25, 1, 20.00, NULL, NULL),
(604, 81, 21, 1, 3.00, NULL, NULL),
(605, 81, 19, 1, 5.00, NULL, NULL),
(606, 81, 23, 1, 10.00, NULL, NULL),
(623, 82, 23, 1, 10.00, NULL, NULL),
(624, 82, 21, 1, 3.00, NULL, NULL),
(625, 82, 16, 1, 2.00, NULL, NULL),
(626, 82, 17, 1, 3.00, NULL, NULL),
(627, 82, 22, 1, 7.00, NULL, NULL),
(628, 82, 25, 1, 20.00, NULL, NULL),
(629, 82, 18, 1, 2.00, NULL, NULL),
(654, 88, 23, 1, 10.00, NULL, NULL),
(655, 88, 22, 1, 7.00, NULL, NULL),
(659, 90, 23, 1, 10.00, NULL, NULL),
(660, 90, 18, 1, 2.00, NULL, NULL),
(661, 90, 25, 1, 20.00, NULL, NULL),
(662, 90, 16, 1, 2.00, NULL, NULL),
(663, 91, 23, 1, 10.00, NULL, NULL),
(664, 91, 16, 1, 2.00, NULL, NULL),
(669, 93, 23, 1, 10.00, NULL, NULL),
(670, 93, 25, 1, 20.00, NULL, NULL),
(671, 93, 18, 1, 2.00, NULL, NULL),
(672, 93, 17, 1, 3.00, NULL, NULL),
(673, 94, 23, 2, 10.00, NULL, NULL),
(674, 94, 25, 1, 20.00, NULL, NULL),
(675, 94, 17, 4, 3.00, NULL, NULL),
(676, 94, 22, 1, 7.00, NULL, NULL),
(677, 94, 24, 1, 2.00, NULL, NULL),
(678, 94, 21, 2, 3.00, NULL, NULL),
(679, 94, 20, 1, 1.00, NULL, NULL),
(680, 94, 16, 1, 2.00, NULL, NULL),
(681, 94, 18, 2, 2.00, NULL, NULL),
(694, 96, 23, 1, 10.00, NULL, NULL),
(695, 97, 23, 1, 10.00, NULL, NULL),
(696, 97, 25, 8, 20.00, NULL, NULL),
(697, 97, 21, 1, 3.00, NULL, NULL),
(698, 97, 16, 4, 2.00, NULL, NULL),
(699, 97, 20, 2, 1.00, NULL, NULL),
(700, 97, 24, 1, 2.00, NULL, NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detecciones`
--

CREATE TABLE `detecciones` (
  `id` int(11) NOT NULL,
  `venta_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `confianza` float NOT NULL,
  `procesada` tinyint(1) NOT NULL DEFAULT 0,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `intentos_login`
--

CREATE TABLE `intentos_login` (
  `usuario` varchar(100) NOT NULL,
  `intentos` int(11) NOT NULL DEFAULT 0,
  `ultimo_fallo` datetime NOT NULL,
  `bloqueado_hasta` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `productos`
--

CREATE TABLE `productos` (
  `id` int(11) NOT NULL,
  `nombre` varchar(150) NOT NULL,
  `precio` decimal(10,2) NOT NULL CHECK (`precio` >= 0),
  `categoria_id` int(11) NOT NULL,
  `clase_modelo` varchar(100) NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `stock` int(11) NOT NULL DEFAULT 100,
  `stock_minimo` int(11) NOT NULL DEFAULT 5
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `productos`
--

INSERT INTO `productos` (`id`, `nombre`, `precio`, `categoria_id`, `clase_modelo`, `activo`, `creado_en`, `actualizado_en`, `stock`, `stock_minimo`) VALUES
(1, 'churrasco', 3.00, 2, 'churrasco', 0, '2026-10-03 20:12:56', '2026-11-22 00:25:26', 143, 5),
(2, 'ta_bueno', 2.00, 1, 'ta_bueno', 0, '2026-10-03 20:14:29', '2026-11-22 00:25:24', 118, 5),
(3, 'chizito', 2.00, 1, 'chizito', 0, '2026-10-03 20:20:28', '2026-11-22 00:25:15', 1, 5),
(4, 'mostaza', 4.00, 3, 'mostaza', 0, '2026-10-03 20:21:38', '2026-10-04 02:59:45', 100, 5),
(6, 'mostaza', 4.00, 3, 'mostaza_1791083124', 0, '2026-10-04 03:05:24', '2026-11-22 00:25:23', 118, 5),
(7, 'chipchip', 2.00, 2, 'chipchip_1791204719', 0, '2026-10-05 12:51:59', '2026-11-22 00:25:17', 2, 5),
(8, 'cocacola', 5.00, 2, 'cocacola_1791205074', 0, '2026-10-05 12:57:54', '2026-11-22 00:25:21', 27, 5),
(9, 'Gomitas Miaw', 2.00, 8, 'gomitas_miaw_1795308119', 0, '2026-11-22 00:41:59', '2026-11-22 15:58:28', 10, 5),
(10, 'Bon o Bon', 3.00, 6, 'bon_o_bon_1795308179', 0, '2026-11-22 00:42:59', '2026-11-22 15:58:30', 20, 5),
(11, 'Pinzones Grageas', 4.00, 6, 'pinzones_grageas_1795308248', 0, '2026-11-22 00:44:08', '2026-11-22 15:58:33', 20, 5),
(12, 'Chubi', 5.00, 6, 'chubi_1795308290', 0, '2026-11-22 00:44:50', '2026-11-22 15:58:31', 20, 5),
(13, 'Happy Chocolate', 2.00, 6, 'happy_chocolate_1795308336', 0, '2026-11-22 00:45:36', '2026-11-22 15:58:34', 30, 5),
(14, 'Gelatina Araña', 2.00, 7, 'gelatina_araña_1795308397', 0, '2026-11-22 00:46:37', '2026-11-22 01:38:20', 20, 5),
(15, 'Chubi', 3.00, 6, 'chubi_1795363325', 1, '2026-11-22 16:02:05', '2026-11-22 16:02:05', 20, 5),
(16, 'Gomitas Miaw', 2.00, 8, 'gomitas_miaw_1795364692', 1, '2026-11-22 16:24:52', '2026-11-22 16:24:52', 30, 5),
(17, 'Bon o Bon', 3.00, 6, 'bon_o_bon_1795364769', 1, '2026-11-22 16:26:09', '2026-11-22 16:26:09', 20, 5),
(18, 'Happy Chocolate', 2.00, 6, 'happy_chocolate_1795364864', 1, '2026-11-22 16:27:44', '2026-11-22 16:27:44', 20, 5),
(19, 'Pinzones Grageas', 5.00, 6, 'pinzones_grageas_1795364944', 1, '2026-11-22 16:29:04', '2026-11-22 16:29:04', 20, 5),
(20, 'Rulero', 1.00, 9, 'rulero_1795365178', 1, '2026-11-22 16:32:58', '2026-11-22 16:32:58', 50, 5),
(21, 'Peine', 3.00, 9, 'peine_1795365296', 1, '2026-11-22 16:34:56', '2026-11-22 16:34:56', 30, 5),
(22, 'Labial Colorina', 7.00, 9, 'labial_colorina_1795365392', 1, '2026-11-22 16:36:32', '2026-11-22 16:36:32', 10, 5),
(23, 'Mentisan', 10.00, 11, 'mentisan_1795365516', 1, '2026-11-22 16:38:36', '2026-11-22 16:38:36', 20, 5),
(24, 'Rasuradora', 2.00, 10, 'rasuradora_1795365623', 1, '2026-11-22 16:40:23', '2026-11-22 16:40:23', 50, 5),
(25, 'Hilo Dental', 20.00, 10, 'hilo_dental_1795365737', 1, '2026-11-22 16:42:17', '2026-11-22 16:42:17', 20, 5),
(26, 'Nivea', 15.00, 4, 'nivea_1795442835', 1, '2026-11-23 14:07:15', '2026-11-23 14:07:15', 20, 5);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `promociones`
--

CREATE TABLE `promociones` (
  `id` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `tipo` enum('producto','categoria') NOT NULL,
  `producto_id` int(11) DEFAULT NULL,
  `categoria_id` int(11) DEFAULT NULL,
  `porcentaje` decimal(5,2) NOT NULL,
  `fecha_inicio` date NOT NULL,
  `fecha_fin` date NOT NULL,
  `activa` tinyint(1) NOT NULL DEFAULT 1,
  `desactivada_auto_en` timestamp NULL DEFAULT NULL,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

--
-- Volcado de datos para la tabla `promociones`
--

INSERT INTO `promociones` (`id`, `nombre`, `tipo`, `producto_id`, `categoria_id`, `porcentaje`, `fecha_inicio`, `fecha_fin`, `activa`, `desactivada_auto_en`, `creado_en`, `actualizado_en`) VALUES
(2, 'Mitad de descuento PAPAS', 'producto', 2, NULL, 50.00, '2026-11-18', '2026-11-22', 0, NULL, '2026-11-18 05:30:01', '2026-11-22 00:26:30');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `proveedores`
--

CREATE TABLE `proveedores` (
  `id` int(11) NOT NULL,
  `razon_social` varchar(150) NOT NULL,
  `nit` varchar(30) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `correo` varchar(100) DEFAULT NULL,
  `direccion` varchar(150) DEFAULT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `proveedores`
--

INSERT INTO `proveedores` (`id`, `razon_social`, `nit`, `telefono`, `correo`, `direccion`, `activo`, `creado_en`) VALUES
(1, 'Distribuidora Andina S.R.L.', '1020304050', '70011223', 'ventas@andina.bo', 'Av. Blanco Galindo km 4', 1, '2026-11-18 04:26:42'),
(2, 'Embol S.A.', '1007039026', '44260000', 'pedidos@embol.bo', 'Av. Petrolera km 6', 1, '2026-11-18 04:26:42'),
(3, 'Proveedor sin compras', '9988776655', '70099887', NULL, NULL, 1, '2026-11-18 04:26:42');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `usuarios`
--

CREATE TABLE `usuarios` (
  `id` int(11) NOT NULL,
  `username` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `rol` enum('administrador','cajero','cliente') NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `usuarios`
--

INSERT INTO `usuarios` (`id`, `username`, `password`, `rol`, `activo`, `creado_en`) VALUES
(1, 'admin', '$2b$12$BtH.YQWAFAjSP.nCtxiUvuuyI4.crFxzlTmZlaWXO6GjHT8mwtnqq', 'administrador', 1, '2026-10-04 03:24:50'),
(2, 'cajero', '$2b$12$916C8retCRtE1QlW/i/tFOxcvXMqNqKOvP4GFt3pZWPZaXnpZAF7G', 'cajero', 1, '2026-10-04 03:24:50'),
(3, 'cliente', '$2b$12$AGSPvdClTHNjpfdVgSHooeOXktLpZK32qFAIAQSmm2L4YtnMsIVr2', 'cliente', 1, '2026-10-04 03:24:50'),
(4, 'Pablo', '$2b$12$1OLQMOF5y/zKekY4rGvwSukvv5.hCPWylo9RWfCLpodH1RuA/n1NO', 'cajero', 0, '2026-11-18 10:42:27');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ventas`
--

CREATE TABLE `ventas` (
  `id` int(11) NOT NULL,
  `estado` varchar(20) NOT NULL DEFAULT 'en_progreso',
  `total` decimal(10,2) NOT NULL DEFAULT 0.00,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `metodo_pago` varchar(20) NOT NULL DEFAULT 'efectivo',
  `monto_recibido` decimal(10,2) DEFAULT NULL,
  `cambio` decimal(10,2) DEFAULT NULL,
  `cliente_tipo_documento` varchar(20) DEFAULT NULL,
  `cliente_direccion` varchar(150) DEFAULT NULL,
  `cliente_usuario_id` int(11) DEFAULT NULL,
  `factura` tinyint(1) NOT NULL DEFAULT 0,
  `cliente_nombre` varchar(100) DEFAULT NULL,
  `cliente_documento` varchar(20) DEFAULT NULL,
  `cliente_email` varchar(100) DEFAULT NULL,
  `cliente_telefono` varchar(20) DEFAULT NULL,
  `cajero` varchar(50) DEFAULT NULL,
  `nota` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Volcado de datos para la tabla `ventas`
--

INSERT INTO `ventas` (`id`, `estado`, `total`, `creado_en`, `metodo_pago`, `monto_recibido`, `cambio`, `cliente_tipo_documento`, `cliente_direccion`, `cliente_usuario_id`, `factura`, `cliente_nombre`, `cliente_documento`, `cliente_email`, `cliente_telefono`, `cajero`, `nota`) VALUES
(1, 'en_progreso', 0.00, '2026-10-03 20:22:42', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(2, 'en_progreso', 4.00, '2026-10-03 20:22:51', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(3, 'en_progreso', 0.00, '2026-10-04 03:40:27', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(4, 'en_progreso', 0.00, '2026-10-04 03:41:01', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(5, 'en_progreso', 0.00, '2026-10-04 03:41:33', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(6, 'en_progreso', 0.00, '2026-10-04 04:05:02', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(7, 'en_progreso', 0.00, '2026-10-04 04:05:24', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(8, 'en_progreso', 0.00, '2026-10-04 04:06:17', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(9, 'en_progreso', 0.00, '2026-10-04 04:28:10', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(10, 'en_progreso', 2.00, '2026-10-04 19:22:15', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(18, 'finalizada', 2.00, '2026-10-04 19:30:17', 'tarjeta', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(19, 'en_progreso', 6.00, '2026-10-05 12:52:35', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(20, 'en_progreso', 63.00, '2026-10-05 12:58:14', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(21, 'en_progreso', 0.00, '2026-10-21 12:04:04', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(22, 'en_progreso', 4.00, '2026-10-25 23:53:41', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(23, 'finalizada', 4.00, '2026-10-26 01:10:05', 'qr', NULL, NULL, 'CI', 'calle', NULL, 0, 'wil', '10325319', 'wildercrk@gmail.com', '645243', 'cajero', NULL),
(24, 'en_progreso', 4.00, '2026-10-26 01:17:08', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(25, 'finalizada', 4.00, '2026-10-26 01:30:00', 'efectivo', 10.00, 6.00, 'CI', 'siempre viva', NULL, 0, NULL, '123456789', 'jose@gmail.com', '145625478', 'cajero', NULL),
(26, 'finalizada', 6.00, '2026-10-26 01:31:45', 'efectivo', 20.00, 14.00, 'CI', 'Av. marcelo', NULL, 0, NULL, '123456789', 'jose@gmail.com', '1245789', 'cajero', NULL),
(27, 'en_progreso', 4.00, '2026-10-26 01:33:57', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(28, 'en_progreso', 2.00, '2026-10-26 01:41:35', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(29, 'finalizada', 4.00, '2026-10-26 01:53:03', 'efectivo', 50.00, 46.00, 'CI', 'calle', NULL, 0, 'wilder', '10325319', 'wildercrk@gmail.com', '645243', 'cajero', NULL),
(30, 'finalizada', 4.00, '2026-10-26 01:56:47', 'efectivo', 10.00, 6.00, 'CI', 'millares', NULL, 0, 'jose', '10304050', 'jose@gmail.com', '123456789', 'cajero', NULL),
(31, 'finalizada', 2.00, '2026-10-26 01:58:57', 'efectivo', 5.00, 3.00, 'CI', 'millares', NULL, 0, 'jose Duran', '10304050', 'jose@gmail.com', '123456789', 'cajero', NULL),
(32, 'finalizada', 6.00, '2026-10-26 02:57:36', 'efectivo', 6.00, 0.00, 'CI', 'millares', NULL, 0, 'jose Duran', '10304050', 'jose@gmail.com', '123456789', 'cajero', NULL),
(33, 'pendiente', 4.00, '2026-10-26 11:45:01', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(34, 'pendiente', 4.00, '2026-10-26 11:45:10', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(35, 'pendiente', 6.00, '2026-10-26 11:45:16', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(36, 'pendiente', 6.00, '2026-10-26 11:45:22', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(37, 'pendiente', 2.00, '2026-10-26 11:45:28', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(38, 'pendiente', 2.00, '2026-10-26 11:45:34', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(39, 'pendiente', 2.00, '2026-10-26 11:45:36', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(40, 'pendiente', 2.00, '2026-10-26 11:45:43', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(41, 'listo', 2.00, '2026-10-26 11:46:40', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(42, 'listo', 2.00, '2026-10-26 11:46:51', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(43, 'listo', 9.00, '2026-10-26 11:47:05', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(44, 'listo', 5.00, '2026-10-26 11:47:15', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(45, 'pendiente', 5.00, '2026-10-26 11:47:27', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(46, 'pendiente', 5.00, '2026-10-26 11:47:36', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(47, 'listo', 10.00, '2026-10-26 11:47:46', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(48, 'pendiente', 10.00, '2026-10-26 11:47:48', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', NULL, NULL),
(49, 'listo', 5.00, '2026-10-26 11:48:06', 'efectivo', NULL, NULL, NULL, NULL, 3, 0, 'Cliente Prueba', NULL, NULL, '71234567', 'cajero', NULL),
(50, 'en_progreso', 0.00, '2026-11-18 10:31:45', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(51, 'en_progreso', 1.00, '2026-11-18 12:45:20', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(52, 'en_progreso', 0.00, '2026-11-18 16:08:04', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(53, 'en_progreso', 0.00, '2026-11-22 01:20:58', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(54, 'en_progreso', 11.00, '2026-11-22 01:38:49', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(55, 'en_progreso', 0.00, '2026-11-22 05:42:29', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(56, 'en_progreso', 17.00, '2026-11-22 05:54:37', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(57, 'en_progreso', 0.00, '2026-11-22 09:44:44', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(58, 'en_progreso', 0.00, '2026-11-22 09:50:26', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(59, 'en_progreso', 0.00, '2026-11-22 09:56:18', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(60, 'en_progreso', 16.00, '2026-11-22 09:57:26', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(61, 'en_progreso', 0.00, '2026-11-22 09:59:24', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(62, 'en_progreso', 0.00, '2026-11-22 10:00:30', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(63, 'en_progreso', 0.00, '2026-11-22 10:00:46', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(64, 'en_progreso', 10.00, '2026-11-22 10:02:00', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(65, 'en_progreso', 0.00, '2026-11-22 13:23:49', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(66, 'en_progreso', 23.00, '2026-11-22 13:28:59', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(67, 'en_progreso', 16.00, '2026-11-22 14:44:03', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(68, 'en_progreso', 0.00, '2026-11-22 14:54:04', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(69, 'en_progreso', 3.00, '2026-11-22 15:12:58', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(70, 'en_progreso', 101.00, '2026-11-22 18:33:04', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(71, 'en_progreso', 0.00, '2026-11-22 18:55:59', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(72, 'en_progreso', 0.00, '2026-11-22 19:16:23', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(73, 'en_progreso', 7.00, '2026-11-22 22:24:52', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(74, 'en_progreso', 10.00, '2026-11-22 22:36:52', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(75, 'en_progreso', 0.00, '2026-11-22 22:43:02', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(76, 'en_progreso', 0.00, '2026-11-22 22:46:06', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(77, 'en_progreso', 0.00, '2026-11-22 22:48:05', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(78, 'en_progreso', 0.00, '2026-11-22 22:53:08', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(79, 'en_progreso', 36.00, '2026-11-22 22:58:51', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(80, 'en_progreso', 0.00, '2026-11-22 23:02:45', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(81, 'en_progreso', 42.00, '2026-11-22 23:05:43', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(82, 'en_progreso', 47.00, '2026-11-22 23:08:04', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(83, 'en_progreso', 0.00, '2026-11-23 12:38:48', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(84, 'en_progreso', 0.00, '2026-11-23 12:44:32', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(85, 'en_progreso', 0.00, '2026-11-23 12:45:38', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(86, 'en_progreso', 0.00, '2026-11-23 12:53:52', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(87, 'en_progreso', 0.00, '2026-11-23 13:04:43', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(88, 'en_progreso', 17.00, '2026-11-23 13:30:10', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(89, 'en_progreso', 0.00, '2026-11-23 13:38:19', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(90, 'en_progreso', 34.00, '2026-11-23 13:40:20', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(91, 'en_progreso', 12.00, '2026-11-23 13:42:05', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(92, 'en_progreso', 0.00, '2026-11-23 13:42:58', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(93, 'en_progreso', 35.00, '2026-11-23 13:43:56', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(94, 'en_progreso', 74.00, '2026-11-23 13:46:24', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(95, 'en_progreso', 0.00, '2026-11-23 14:08:00', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(96, 'en_progreso', 10.00, '2026-11-23 14:10:34', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL),
(97, 'en_progreso', 185.00, '2026-11-23 14:12:01', 'efectivo', NULL, NULL, NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL);

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `categorias`
--
ALTER TABLE `categorias`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `nombre` (`nombre`);

--
-- Indices de la tabla `clientes`
--
ALTER TABLE `clientes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_clientes_documento` (`documento`),
  ADD UNIQUE KEY `usuario_id` (`usuario_id`);

--
-- Indices de la tabla `compras`
--
ALTER TABLE `compras`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_compras_proveedor` (`proveedor_id`),
  ADD KEY `fk_compras_usuario` (`usuario_id`);

--
-- Indices de la tabla `detalle_compra`
--
ALTER TABLE `detalle_compra`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_detalle_compra_compra` (`compra_id`),
  ADD KEY `idx_detalle_compra_producto` (`producto_id`);

--
-- Indices de la tabla `detalle_venta`
--
ALTER TABLE `detalle_venta`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_venta_producto` (`venta_id`,`producto_id`),
  ADD KEY `producto_id` (`producto_id`),
  ADD KEY `idx_detalle_venta_promocion` (`promocion_id`);

--
-- Indices de la tabla `detecciones`
--
ALTER TABLE `detecciones`
  ADD PRIMARY KEY (`id`),
  ADD KEY `venta_id` (`venta_id`),
  ADD KEY `producto_id` (`producto_id`);

--
-- Indices de la tabla `intentos_login`
--
ALTER TABLE `intentos_login`
  ADD PRIMARY KEY (`usuario`);

--
-- Indices de la tabla `productos`
--
ALTER TABLE `productos`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `clase_modelo` (`clase_modelo`),
  ADD KEY `idx_productos_clase_modelo` (`clase_modelo`),
  ADD KEY `idx_productos_categoria` (`categoria_id`);

--
-- Indices de la tabla `promociones`
--
ALTER TABLE `promociones`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_promociones_producto` (`producto_id`),
  ADD KEY `idx_promociones_categoria` (`categoria_id`),
  ADD KEY `idx_promociones_vigencia` (`activa`,`fecha_inicio`,`fecha_fin`);

--
-- Indices de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_proveedores_nit` (`nit`);

--
-- Indices de la tabla `usuarios`
--
ALTER TABLE `usuarios`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`);

--
-- Indices de la tabla `ventas`
--
ALTER TABLE `ventas`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `categorias`
--
ALTER TABLE `categorias`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT de la tabla `clientes`
--
ALTER TABLE `clientes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `compras`
--
ALTER TABLE `compras`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `detalle_compra`
--
ALTER TABLE `detalle_compra`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT de la tabla `detalle_venta`
--
ALTER TABLE `detalle_venta`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=703;

--
-- AUTO_INCREMENT de la tabla `detecciones`
--
ALTER TABLE `detecciones`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=1692;

--
-- AUTO_INCREMENT de la tabla `productos`
--
ALTER TABLE `productos`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=27;

--
-- AUTO_INCREMENT de la tabla `promociones`
--
ALTER TABLE `promociones`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `proveedores`
--
ALTER TABLE `proveedores`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `usuarios`
--
ALTER TABLE `usuarios`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `ventas`
--
ALTER TABLE `ventas`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=98;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `clientes`
--
ALTER TABLE `clientes`
  ADD CONSTRAINT `fk_clientes_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `compras`
--
ALTER TABLE `compras`
  ADD CONSTRAINT `fk_compras_proveedor` FOREIGN KEY (`proveedor_id`) REFERENCES `proveedores` (`id`),
  ADD CONSTRAINT `fk_compras_usuario` FOREIGN KEY (`usuario_id`) REFERENCES `usuarios` (`id`);

--
-- Filtros para la tabla `detalle_compra`
--
ALTER TABLE `detalle_compra`
  ADD CONSTRAINT `fk_detalle_compra_compra` FOREIGN KEY (`compra_id`) REFERENCES `compras` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_detalle_compra_producto` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`);

--
-- Filtros para la tabla `detalle_venta`
--
ALTER TABLE `detalle_venta`
  ADD CONSTRAINT `detalle_venta_ibfk_1` FOREIGN KEY (`venta_id`) REFERENCES `ventas` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `detalle_venta_ibfk_2` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`),
  ADD CONSTRAINT `fk_detalle_venta_promocion` FOREIGN KEY (`promocion_id`) REFERENCES `promociones` (`id`) ON DELETE SET NULL;

--
-- Filtros para la tabla `detecciones`
--
ALTER TABLE `detecciones`
  ADD CONSTRAINT `detecciones_ibfk_1` FOREIGN KEY (`venta_id`) REFERENCES `ventas` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `detecciones_ibfk_2` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`);

--
-- Filtros para la tabla `productos`
--
ALTER TABLE `productos`
  ADD CONSTRAINT `fk_productos_categoria` FOREIGN KEY (`categoria_id`) REFERENCES `categorias` (`id`) ON UPDATE CASCADE;

--
-- Filtros para la tabla `promociones`
--
ALTER TABLE `promociones`
  ADD CONSTRAINT `fk_promociones_categoria` FOREIGN KEY (`categoria_id`) REFERENCES `categorias` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_promociones_producto` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
