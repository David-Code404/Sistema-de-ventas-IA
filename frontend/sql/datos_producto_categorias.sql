-- MariaDB dump 10.19  Distrib 10.4.32-MariaDB, for Win64 (AMD64)
--
-- Host: localhost    Database: caja_registradora_ia
-- ------------------------------------------------------
-- Server version	10.4.32-MariaDB

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `categorias`
--

DROP TABLE IF EXISTS `categorias`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `categorias` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `nombre` varchar(100) NOT NULL,
  `descripcion` varchar(255) DEFAULT NULL,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `color` varchar(7) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `nombre` (`nombre`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `categorias`
--

LOCK TABLES `categorias` WRITE;
/*!40000 ALTER TABLE `categorias` DISABLE KEYS */;
INSERT INTO `categorias` VALUES (1,'Papas fritas','Snacks de papa frita en bolsa','2026-09-09 07:10:16',NULL),(2,'Snacks','Snacks salados que no son papa frita, ej. tipo cheetos','2026-09-09 07:10:16',NULL),(3,'Condimentos','Salsas y condimentos para acompañar comidas','2026-09-09 07:10:16',NULL),(4,'Cuidado personal','Productos de higiene y cuidado personal','2026-09-09 07:10:16',NULL);
/*!40000 ALTER TABLE `categorias` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `detalle_venta`
--

DROP TABLE IF EXISTS `detalle_venta`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `detalle_venta` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `venta_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL DEFAULT 1,
  `precio_unitario` decimal(10,2) NOT NULL,
  `subtotal` decimal(10,2) GENERATED ALWAYS AS (`cantidad` * `precio_unitario`) STORED,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_venta_producto` (`venta_id`,`producto_id`),
  KEY `producto_id` (`producto_id`),
  CONSTRAINT `detalle_venta_ibfk_1` FOREIGN KEY (`venta_id`) REFERENCES `ventas` (`id`) ON DELETE CASCADE,
  CONSTRAINT `detalle_venta_ibfk_2` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=31 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `detalle_venta`
--

LOCK TABLES `detalle_venta` WRITE;
/*!40000 ALTER TABLE `detalle_venta` DISABLE KEYS */;
INSERT INTO `detalle_venta` VALUES (1,2,4,1,4.00,4.00),(5,11,3,1,2.00,2.00),(6,12,3,1,2.00,2.00),(7,13,3,1,2.00,2.00),(8,14,3,1,2.00,2.00),(9,14,2,1,2.00,2.00),(10,15,3,1,2.00,2.00),(11,16,3,1,2.00,2.00),(13,18,3,1,2.00,2.00),(30,29,3,1,2.00,2.00);
/*!40000 ALTER TABLE `detalle_venta` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `detecciones`
--

DROP TABLE IF EXISTS `detecciones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `detecciones` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `venta_id` int(11) NOT NULL,
  `producto_id` int(11) NOT NULL,
  `confianza` float NOT NULL,
  `procesada` tinyint(1) NOT NULL DEFAULT 0,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `venta_id` (`venta_id`),
  KEY `producto_id` (`producto_id`),
  CONSTRAINT `detecciones_ibfk_1` FOREIGN KEY (`venta_id`) REFERENCES `ventas` (`id`) ON DELETE CASCADE,
  CONSTRAINT `detecciones_ibfk_2` FOREIGN KEY (`producto_id`) REFERENCES `productos` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1692 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `detecciones`
--

LOCK TABLES `detecciones` WRITE;
/*!40000 ALTER TABLE `detecciones` DISABLE KEYS */;
/*!40000 ALTER TABLE `detecciones` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `productos`
--

DROP TABLE IF EXISTS `productos`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `productos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `nombre` varchar(150) NOT NULL,
  `precio` decimal(10,2) NOT NULL CHECK (`precio` >= 0),
  `categoria_id` int(11) NOT NULL,
  `clase_modelo` varchar(100) NOT NULL,
  `activo` tinyint(1) NOT NULL DEFAULT 1,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `stock` int(11) NOT NULL DEFAULT 100,
  PRIMARY KEY (`id`),
  UNIQUE KEY `clase_modelo` (`clase_modelo`),
  KEY `idx_productos_clase_modelo` (`clase_modelo`),
  KEY `idx_productos_categoria` (`categoria_id`),
  CONSTRAINT `fk_productos_categoria` FOREIGN KEY (`categoria_id`) REFERENCES `categorias` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `productos`
--

LOCK TABLES `productos` WRITE;
/*!40000 ALTER TABLE `productos` DISABLE KEYS */;
INSERT INTO `productos` VALUES (1,'churrasco',3.00,2,'churrasco',1,'2026-10-03 20:12:56','2026-10-03 20:12:56',100),(2,'ta_bueno',2.00,1,'ta_bueno',1,'2026-10-03 20:14:29','2026-10-03 20:14:29',100),(3,'chizito',2.00,1,'chizito',1,'2026-10-03 20:20:28','2026-10-04 02:53:40',100),(4,'mostaza',4.00,3,'mostaza',0,'2026-10-03 20:21:38','2026-10-04 02:59:45',100),(6,'mostaza',4.00,3,'mostaza_1791083124',1,'2026-10-04 03:05:24','2026-10-04 03:05:24',100);
/*!40000 ALTER TABLE `productos` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `usuarios`
--

DROP TABLE IF EXISTS `usuarios`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `usuarios` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `rol` enum('administrador','cajero','cliente') NOT NULL,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `usuarios`
--

LOCK TABLES `usuarios` WRITE;
/*!40000 ALTER TABLE `usuarios` DISABLE KEYS */;
INSERT INTO `usuarios` VALUES (1,'admin','$2b$12$BtH.YQWAFAjSP.nCtxiUvuuyI4.crFxzlTmZlaWXO6GjHT8mwtnqq','administrador','2026-10-04 03:24:50'),(2,'cajero','$2b$12$916C8retCRtE1QlW/i/tFOxcvXMqNqKOvP4GFt3pZWPZaXnpZAF7G','cajero','2026-10-04 03:24:50'),(3,'cliente','$2b$12$AGSPvdClTHNjpfdVgSHooeOXktLpZK32qFAIAQSmm2L4YtnMsIVr2','cliente','2026-10-04 03:24:50');
/*!40000 ALTER TABLE `usuarios` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ventas`
--

DROP TABLE IF EXISTS `ventas`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ventas` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `estado` varchar(20) NOT NULL DEFAULT 'en_progreso',
  `total` decimal(10,2) NOT NULL DEFAULT 0.00,
  `creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `metodo_pago` varchar(20) NOT NULL DEFAULT 'efectivo',
  `monto_recibido` decimal(10,2) DEFAULT NULL,
  `cambio` decimal(10,2) DEFAULT NULL,
  `factura` tinyint(1) NOT NULL DEFAULT 0,
  `cliente_nombre` varchar(100) DEFAULT NULL,
  `cliente_documento` varchar(20) DEFAULT NULL,
  `cliente_email` varchar(100) DEFAULT NULL,
  `cliente_telefono` varchar(20) DEFAULT NULL,
  `cajero` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=30 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ventas`
--

LOCK TABLES `ventas` WRITE;
/*!40000 ALTER TABLE `ventas` DISABLE KEYS */;
INSERT INTO `ventas` VALUES (1,'en_progreso',0.00,'2026-10-03 20:22:42','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(2,'en_progreso',4.00,'2026-10-03 20:22:51','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(3,'en_progreso',0.00,'2026-10-04 03:40:27','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(4,'en_progreso',0.00,'2026-10-04 03:41:01','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(5,'en_progreso',0.00,'2026-10-04 03:41:33','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(6,'en_progreso',0.00,'2026-10-04 04:05:02','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(7,'en_progreso',0.00,'2026-10-04 04:05:24','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(8,'en_progreso',0.00,'2026-10-04 04:06:17','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(9,'en_progreso',0.00,'2026-10-04 04:28:10','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(11,'finalizada',2.00,'2026-10-04 14:14:03','efectivo',2.00,0.00,0,NULL,NULL,NULL,NULL,NULL),(12,'finalizada',2.00,'2026-10-04 14:18:31','qr',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(13,'finalizada',2.00,'2026-10-04 14:35:04','qr',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(14,'en_progreso',4.00,'2026-10-04 14:35:43','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(15,'finalizada',2.00,'2026-10-04 14:45:47','qr',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(16,'finalizada',2.00,'2026-10-04 15:38:35','efectivo',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(18,'finalizada',2.00,'2026-10-04 15:51:45','qr',NULL,NULL,0,NULL,NULL,NULL,NULL,NULL),(29,'finalizada',2.00,'2026-10-05 02:22:04','qr',NULL,NULL,1,'dasd','8519137',NULL,NULL,NULL);
/*!40000 ALTER TABLE `ventas` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-10-04 22:50:56
