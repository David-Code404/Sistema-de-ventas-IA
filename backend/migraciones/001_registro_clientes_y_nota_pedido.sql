-- ============================================================
-- HU-18_980  Seleccion de productos del catalogo en linea y creacion del pedido
-- Base de datos: caja_registradora_ia
--
-- Ejecutar UNA sola vez (phpMyAdmin > SQL, o: mysql -u root caja_registradora_ia < este_archivo).
-- Solo agrega columnas o amplia una existente: no borra datos.
-- ============================================================

-- 1. Los clientes inician sesion con su correo (antes el limite era 50 caracteres)
ALTER TABLE usuarios
  MODIFY username VARCHAR(100) NOT NULL;

-- 2. Vincula la ficha del cliente (tabla clientes) con su cuenta (tabla usuarios).
--    NULL = cliente registrado por el cajero en una venta, sin cuenta en linea.
ALTER TABLE clientes
  ADD COLUMN usuario_id INT NULL UNIQUE,
  ADD CONSTRAINT fk_clientes_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id);

-- 3. Descripcion opcional del pedido ("todo en 2 bolsas", "paso a recoger a las 6 pm").
--    Los pedidos se guardan en ventas con estado 'pendiente' (estructura de HU-18_990).
ALTER TABLE ventas
  ADD COLUMN nota VARCHAR(255) NULL;
