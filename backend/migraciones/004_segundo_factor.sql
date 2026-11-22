-- ============================================================
-- HU-24_1310 / 1330  Segundo factor de autenticacion por correo
-- Base de datos: caja_registradora_ia
--
-- NO hace falta ejecutarlo a mano: el backend crea estas tablas solas la primera vez que se usa el
-- segundo factor (backend/modelo/segundo_factor.py). Queda aqui como referencia.
-- Solo crea tablas nuevas: no toca usuarios ni clientes.
--
-- Reglas: administrador y cajero -> obligatorio; cliente -> opcional (lo activa desde su cuenta).
-- Codigo de 6 digitos, vale 5 minutos, un solo uso, 5 intentos. Los codigos no se guardan, solo su huella.
-- ============================================================
CREATE TABLE IF NOT EXISTS segundo_factor_usuario (
  usuario_id INT          NOT NULL,
  correo     VARCHAR(100) NULL,        -- donde llega el codigo (si es NULL se usa clientes.email)
  activo     TINYINT(1)   NOT NULL DEFAULT 0,   -- solo cuenta para clientes
  PRIMARY KEY (usuario_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS codigos_2fa (
  reto          CHAR(64) NOT NULL,     -- huella del identificador de este inicio de sesion
  usuario_id    INT      NOT NULL,
  codigo_hash   CHAR(64) NULL,
  codigo_expira DATETIME NULL,
  intentos      INT      NOT NULL DEFAULT 0,
  envios        INT      NOT NULL DEFAULT 0,
  enviado_en    DATETIME NULL,
  usado         TINYINT(1) NOT NULL DEFAULT 0,
  reto_expira   DATETIME NOT NULL,
  PRIMARY KEY (reto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
