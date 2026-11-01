-- Verificacion en dos pasos (TOTP) y codigos de respaldo.
-- Ejecutar UNA sola vez (phpMyAdmin > SQL, o: mysql -u root caja_registradora_ia < este_archivo).
-- Solo agrega columnas: no borra datos.

ALTER TABLE usuarios
  ADD COLUMN totp_secret VARCHAR(64) NULL,
  ADD COLUMN totp_activo TINYINT(1) NOT NULL DEFAULT 0,
  ADD COLUMN codigos_respaldo TEXT NULL;
