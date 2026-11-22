-- ============================================================
-- HU-24_1320  Bloqueo temporal tras 3 intentos fallidos de inicio de sesion
-- Base de datos: caja_registradora_ia
--
-- NO hace falta ejecutarlo a mano: el backend crea esta tabla sola la primera vez que alguien
-- intenta iniciar sesion (backend/modelo/bloqueo_login.py). Queda aqui como referencia, por si se
-- prefiere crearla antes (phpMyAdmin > SQL, o: mysql -u root caja_registradora_ia < 003_bloqueo_login.sql).
-- Solo crea una tabla nueva: no toca usuarios ni borra datos.
--
-- Reglas: 3 intentos fallidos seguidos -> 5 minutos de bloqueo; un inicio de sesion correcto borra
-- los intentos; los fallos de hace mas de 15 minutos se olvidan. Los valores estan en bloqueo_login.py.
-- ============================================================
CREATE TABLE IF NOT EXISTS intentos_login (
  usuario         VARCHAR(100) NOT NULL,              -- usuario o correo escrito, en minusculas
  intentos        INT          NOT NULL DEFAULT 0,    -- intentos fallidos seguidos
  ultimo_fallo    DATETIME     NOT NULL,
  bloqueado_hasta DATETIME     NULL,                  -- NULL = no esta bloqueado
  PRIMARY KEY (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
