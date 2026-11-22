"""
HU-24 - Tarea 1320: bloqueo temporal del inicio de sesion tras 3 intentos fallidos.
No importa YOLO ni nada de deteccion.

Reglas:
  - Cada contrasena (o usuario) incorrecto suma un intento fallido a ese usuario.
  - Al 3er intento fallido seguido el usuario queda bloqueado MINUTOS_BLOQUEO minutos: mientras tanto
    no puede entrar ni con la contrasena correcta, y los intentos nuevos no alargan el bloqueo.
  - Un inicio de sesion correcto borra los intentos fallidos.
  - Los fallos viejos se olvidan: si pasan MINUTOS_VENTANA minutos sin fallar, el conteo vuelve a 0.
  - Se cuenta por el texto del usuario (sin importar mayusculas), exista o no la cuenta, para que la
    respuesta no revele si un usuario existe.

Los intentos se guardan en la tabla intentos_login (se crea sola la primera vez, backend/migraciones/003).
Si la tabla no se pudiera usar, se guardan en memoria mientras el backend este encendido.
"""

import threading
from datetime import datetime, timedelta

MAX_INTENTOS = 3
MINUTOS_BLOQUEO = 5
MINUTOS_VENTANA = 15

_candado = threading.Lock()
_memoria: dict[str, dict] = {}       # respaldo si la tabla no se puede usar
_tabla_lista: bool | None = None     # None = aun no se intento crearla

_SQL_TABLA = """
CREATE TABLE IF NOT EXISTS intentos_login (
  usuario         VARCHAR(100) NOT NULL,
  intentos        INT          NOT NULL DEFAULT 0,
  ultimo_fallo    DATETIME     NOT NULL,
  bloqueado_hasta DATETIME     NULL,
  PRIMARY KEY (usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
"""


def clave(username) -> str:
    """Usuario normalizado: sin espacios sobrantes ni mayusculas, maximo 100 caracteres."""
    return " ".join(str(username or "").split()).lower()[:100]


# ── Almacenamiento: tabla en la base, o memoria si no se puede ──────────
def _usar_tabla() -> bool:
    global _tabla_lista
    if _tabla_lista is None:
        try:
            import db

            conexion = db._conexion()
            try:
                conexion.cursor().execute(_SQL_TABLA)
                conexion.commit()
            finally:
                conexion.close()
            _tabla_lista = True
        except Exception:
            _tabla_lista = False
    return _tabla_lista


def _leer(k: str) -> dict | None:
    if not _usar_tabla():
        return _memoria.get(k)
    import db

    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute("SELECT intentos, ultimo_fallo, bloqueado_hasta FROM intentos_login WHERE usuario = %s", (k,))
        return cursor.fetchone()
    finally:
        conexion.close()


def _guardar(k: str, intentos: int, ultimo_fallo: datetime, bloqueado_hasta: datetime | None):
    if not _usar_tabla():
        _memoria[k] = {"intentos": intentos, "ultimo_fallo": ultimo_fallo, "bloqueado_hasta": bloqueado_hasta}
        return
    import db

    conexion = db._conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute("SELECT 1 FROM intentos_login WHERE usuario = %s", (k,))
        if cursor.fetchone() is None:
            cursor.execute(
                "INSERT INTO intentos_login (usuario, intentos, ultimo_fallo, bloqueado_hasta) VALUES (%s, %s, %s, %s)",
                (k, intentos, ultimo_fallo, bloqueado_hasta))
        else:
            cursor.execute(
                "UPDATE intentos_login SET intentos = %s, ultimo_fallo = %s, bloqueado_hasta = %s WHERE usuario = %s",
                (intentos, ultimo_fallo, bloqueado_hasta, k))
        conexion.commit()
    finally:
        conexion.close()


def _borrar(k: str):
    if not _usar_tabla():
        _memoria.pop(k, None)
        return
    import db

    conexion = db._conexion()
    try:
        conexion.cursor().execute("DELETE FROM intentos_login WHERE usuario = %s", (k,))
        conexion.commit()
    finally:
        conexion.close()


# ── Reglas ──────────────────────────────────────────────────────────────
def _segundos_restantes(estado: dict | None, ahora: datetime) -> int:
    if not estado or not estado.get("bloqueado_hasta"):
        return 0
    return max(0, int((estado["bloqueado_hasta"] - ahora).total_seconds() + 0.999))


def mensaje_bloqueo(segundos: int) -> str:
    minutos = max(1, -(-segundos // 60))      # redondea hacia arriba
    unidad = "minuto" if minutos == 1 else "minutos"
    return (f"Demasiados intentos fallidos. Tu acceso esta bloqueado temporalmente: "
            f"intenta de nuevo en {minutos} {unidad}.")


def segundos_de_bloqueo(username, ahora: datetime | None = None) -> int:
    """Segundos que le faltan al bloqueo de este usuario (0 si no esta bloqueado)."""
    ahora = ahora or datetime.now()
    with _candado:
        return _segundos_restantes(_leer(clave(username)), ahora)


def registrar_fallo(username, ahora: datetime | None = None) -> dict:
    """
    Anota un intento fallido. Devuelve {"bloqueado": bool, "segundos": int, "intentos_restantes": int}.
    """
    ahora = ahora or datetime.now()
    k = clave(username)
    with _candado:
        estado = _leer(k)
        segundos = _segundos_restantes(estado, ahora)
        if segundos > 0:                      # ya estaba bloqueado: no se alarga
            return {"bloqueado": True, "segundos": segundos, "intentos_restantes": 0}
        intentos = 0
        if estado and ahora - estado["ultimo_fallo"] <= timedelta(minutes=MINUTOS_VENTANA) \
                and not (estado.get("bloqueado_hasta") and estado["bloqueado_hasta"] <= ahora):
            intentos = int(estado["intentos"])
        intentos += 1
        if intentos >= MAX_INTENTOS:
            hasta = ahora + timedelta(minutes=MINUTOS_BLOQUEO)
            _guardar(k, intentos, ahora, hasta)
            return {"bloqueado": True, "segundos": MINUTOS_BLOQUEO * 60, "intentos_restantes": 0}
        _guardar(k, intentos, ahora, None)
        return {"bloqueado": False, "segundos": 0, "intentos_restantes": MAX_INTENTOS - intentos}


def registrar_exito(username):
    """Un inicio de sesion correcto borra los intentos fallidos de ese usuario."""
    with _candado:
        _borrar(clave(username))
