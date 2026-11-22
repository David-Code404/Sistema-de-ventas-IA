"""
HU-24 - Tareas 1310 y 1330: segundo factor de autenticacion por CORREO. No importa YOLO ni nada de deteccion.

Reglas:
  - Administrador y cajero: el segundo factor es OBLIGATORIO en cada inicio de sesion.
  - Cliente: es OPCIONAL, lo activa o desactiva el propio cliente desde su cuenta.
  - Tras escribir bien usuario y contrasena, el sistema genera un codigo de 6 digitos y lo envia al correo.
  - El codigo vale 5 minutos y se usa UNA sola vez. 5 errores lo invalidan; hay que pedir otro.
  - Se puede pedir otro codigo cada 30 segundos, hasta 3 envios por inicio de sesion.
  - Los codigos no se guardan: solo su huella (sha256).
  - Si el correo (SMTP_*) no esta configurado, el segundo factor queda desactivado para no dejar a nadie
    sin poder entrar (ver backend/segundo_factor.md).

Tablas (se crean solas la primera vez, backend/migraciones/004_segundo_factor.sql):
  segundo_factor_usuario(usuario_id, correo, activo)   correo del segundo factor + si el cliente lo activo
  codigos_2fa(reto, usuario_id, ...)                    un "reto" por inicio de sesion con su codigo vigente
"""

import hashlib
import hmac
import re
import secrets
import threading
from datetime import datetime, timedelta

import correo

MINUTOS_CODIGO = 5
MINUTOS_RETO = 10
MAX_INTENTOS_CODIGO = 5
MAX_ENVIOS = 3
SEGUNDOS_REENVIO = 30
ROLES_OBLIGATORIOS = ("administrador", "cajero")

_CORREO_VALIDO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_candado = threading.Lock()
_tablas_listas = False

_SQL_TABLAS = (
    """
    CREATE TABLE IF NOT EXISTS segundo_factor_usuario (
      usuario_id INT          NOT NULL,
      correo     VARCHAR(100) NULL,
      activo     TINYINT(1)   NOT NULL DEFAULT 0,
      PRIMARY KEY (usuario_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
    """
    CREATE TABLE IF NOT EXISTS codigos_2fa (
      reto          CHAR(64) NOT NULL,
      usuario_id    INT      NOT NULL,
      codigo_hash   CHAR(64) NULL,
      codigo_expira DATETIME NULL,
      intentos      INT      NOT NULL DEFAULT 0,
      envios        INT      NOT NULL DEFAULT 0,
      enviado_en    DATETIME NULL,
      usado         TINYINT(1) NOT NULL DEFAULT 0,
      reto_expira   DATETIME NOT NULL,
      PRIMARY KEY (reto)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    """,
)


class ErrorSegundoFactor(Exception):
    """Error de regla (codigo vencido, incorrecto, demasiados envios...). `estado` es el codigo HTTP sugerido."""

    def __init__(self, mensaje: str, estado: int = 422):
        super().__init__(mensaje)
        self.estado = estado


# ── Acceso a la base ─────────────────────────────────────────────────────
def _ejecutar(sql: str, params=(), uno=False, todos=False):
    import db

    global _tablas_listas
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        if not _tablas_listas:
            for tabla in _SQL_TABLAS:
                cursor.execute(tabla)
            _tablas_listas = True
        cursor.execute(sql, params)
        resultado = cursor.fetchone() if uno else cursor.fetchall() if todos else None
        conexion.commit()
        return resultado
    finally:
        conexion.close()


def _huella(texto: str) -> str:
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def enmascarar(direccion: str) -> str:
    """ana.perez@gmail.com -> a*******@gmail.com"""
    usuario, _, dominio = (direccion or "").partition("@")
    return (usuario[:1] + "*" * max(len(usuario) - 1, 1)) + "@" + dominio


def activo_en_el_sistema() -> bool:
    """El segundo factor solo se exige si el correo esta configurado (si no, nadie podria entrar)."""
    return correo.correo_configurado()


# ── Usuario y correo ─────────────────────────────────────────────────────
def usuario_por_id(usuario_id: int) -> dict | None:
    import db

    fila = _ejecutar("SELECT id, username, rol, activo FROM usuarios WHERE id = %s", (usuario_id,), uno=True)
    if not fila or not fila["activo"]:
        return None
    usuario = {"id": fila["id"], "username": fila["username"], "rol": fila["rol"]}
    if fila["rol"] == "cliente":
        usuario["cliente"] = db.obtener_cliente_de_usuario(fila["id"])
    return usuario


def _preferencias(usuario_id: int) -> dict:
    return _ejecutar("SELECT correo, activo FROM segundo_factor_usuario WHERE usuario_id = %s",
                     (usuario_id,), uno=True) or {"correo": None, "activo": 0}


def correo_de(usuario_id: int, rol: str) -> str | None:
    """Correo donde llega el codigo: el guardado para el segundo factor o, si es cliente, el de su ficha."""
    guardado = (_preferencias(usuario_id).get("correo") or "").strip()
    if guardado:
        return guardado
    if rol == "cliente":
        import db

        ficha = db.obtener_cliente_de_usuario(usuario_id) or {}
        return (ficha.get("email") or "").strip() or None
    return None


def estado(usuario_id: int, rol: str) -> dict:
    prefs = _preferencias(usuario_id)
    obligatorio = rol in ROLES_OBLIGATORIOS
    direccion = correo_de(usuario_id, rol)
    return {
        "disponible": activo_en_el_sistema(),
        "obligatorio": obligatorio,
        "activo": True if obligatorio else bool(prefs["activo"]),
        "correo": enmascarar(direccion) if direccion else None,
        "tiene_correo": bool(direccion),
    }


def requiere(usuario: dict) -> bool:
    """¿Este inicio de sesion debe pasar por el codigo del correo?"""
    if not activo_en_el_sistema():
        return False
    if usuario["rol"] in ROLES_OBLIGATORIOS:
        return True
    return bool(_preferencias(usuario["id"])["activo"])


def validar_correo(direccion: str) -> str:
    direccion = (direccion or "").strip()
    if not direccion or len(direccion) > 100 or not _CORREO_VALIDO.match(direccion):
        raise ErrorSegundoFactor("Correo no valido (ejemplo: nombre@correo.com).")
    return direccion


def asegurar_tablas():
    """Crea las tablas si aun no existen."""
    _ejecutar("SELECT 1 AS x", uno=True)


def guardar_correo(usuario_id: int, direccion: str | None):
    """Registra, cambia o (con None) quita el correo del segundo factor de un usuario."""
    with _candado:
        existe = _ejecutar("SELECT 1 AS x FROM segundo_factor_usuario WHERE usuario_id = %s", (usuario_id,), uno=True)
        if existe:
            _ejecutar("UPDATE segundo_factor_usuario SET correo = %s WHERE usuario_id = %s", (direccion, usuario_id))
        elif direccion:
            _ejecutar("INSERT INTO segundo_factor_usuario (usuario_id, correo, activo) VALUES (%s, %s, 0)",
                      (usuario_id, direccion))


def _guardar_preferencias(usuario_id: int, direccion: str | None, activo: bool | None):
    prefs = _preferencias(usuario_id)
    existe = _ejecutar("SELECT 1 AS x FROM segundo_factor_usuario WHERE usuario_id = %s", (usuario_id,), uno=True)
    nuevo_correo = direccion if direccion is not None else prefs["correo"]
    nuevo_activo = int(activo) if activo is not None else int(prefs["activo"])
    if existe:
        _ejecutar("UPDATE segundo_factor_usuario SET correo = %s, activo = %s WHERE usuario_id = %s",
                  (nuevo_correo, nuevo_activo, usuario_id))
    else:
        _ejecutar("INSERT INTO segundo_factor_usuario (usuario_id, correo, activo) VALUES (%s, %s, %s)",
                  (usuario_id, nuevo_correo, nuevo_activo))


def configurar(usuario_id: int, rol: str, activo: bool | None = None, direccion: str | None = None) -> dict:
    """
    Desde la cuenta del usuario (ya confirmo su contrasena). Staff: solo puede cambiar el correo (el segundo
    factor es obligatorio). Cliente: activa/desactiva y puede elegir otro correo.
    """
    if direccion is not None:
        direccion = validar_correo(direccion)
    if activo is False and rol in ROLES_OBLIGATORIOS:
        raise ErrorSegundoFactor("El segundo factor es obligatorio para administradores y cajeros.")
    if not activo_en_el_sistema():
        raise ErrorSegundoFactor("El envio de correos no esta configurado en el servidor.", 503)
    if activo is True and not (direccion or correo_de(usuario_id, rol)):
        raise ErrorSegundoFactor("Escribe el correo donde quieres recibir el codigo.")
    with _candado:
        _guardar_preferencias(usuario_id, direccion, activo if rol == "cliente" else None)
    return estado(usuario_id, rol)


# ── Retos y codigos ──────────────────────────────────────────────────────
def crear_reto(usuario_id: int, ahora: datetime | None = None) -> str:
    ahora = ahora or datetime.now()
    reto = secrets.token_urlsafe(32)
    with _candado:
        # los retos viejos de este usuario ya no sirven
        _ejecutar("DELETE FROM codigos_2fa WHERE usuario_id = %s", (usuario_id,))
        _ejecutar("INSERT INTO codigos_2fa (reto, usuario_id, reto_expira) VALUES (%s, %s, %s)",
                  (_huella(reto), usuario_id, ahora + timedelta(minutes=MINUTOS_RETO)))
    return reto


def _leer_reto(reto: str, ahora: datetime) -> dict:
    fila = _ejecutar("SELECT * FROM codigos_2fa WHERE reto = %s", (_huella(reto or ""),), uno=True)
    if not fila or fila["usado"] or fila["reto_expira"] <= ahora:
        raise ErrorSegundoFactor("La verificacion expiro. Vuelve a iniciar sesion.", 401)
    return fila


def _codigo_hash(reto: str, codigo: str) -> str:
    return _huella(_huella(reto) + ":" + codigo)


def enviar_codigo(reto: str, ahora: datetime | None = None) -> str:
    """Genera un codigo nuevo y lo envia al correo. Devuelve el correo enmascarado."""
    ahora = ahora or datetime.now()
    with _candado:
        fila = _leer_reto(reto, ahora)
        usuario = usuario_por_id(fila["usuario_id"])
        if usuario is None:
            raise ErrorSegundoFactor("La cuenta no esta disponible.", 401)
        direccion = correo_de(usuario["id"], usuario["rol"])
        if not direccion:
            raise ErrorSegundoFactor("Falta registrar el correo para recibir el codigo.", 409)
        if fila["envios"] >= MAX_ENVIOS:
            raise ErrorSegundoFactor("Ya se enviaron demasiados codigos. Vuelve a iniciar sesion.", 429)
        if fila["enviado_en"] and (ahora - fila["enviado_en"]).total_seconds() < SEGUNDOS_REENVIO:
            falta = int(SEGUNDOS_REENVIO - (ahora - fila["enviado_en"]).total_seconds()) + 1
            raise ErrorSegundoFactor(f"Espera {falta} segundos para pedir otro codigo.", 429)
        codigo = f"{secrets.randbelow(10 ** 6):06d}"
        _ejecutar(
            "UPDATE codigos_2fa SET codigo_hash = %s, codigo_expira = %s, intentos = 0, envios = envios + 1, "
            "enviado_en = %s WHERE reto = %s",
            (_codigo_hash(reto, codigo), ahora + timedelta(minutes=MINUTOS_CODIGO), ahora, _huella(reto)))
    try:
        correo.enviar_codigo_verificacion(direccion, codigo, MINUTOS_CODIGO)
    except correo.CorreoError as e:
        with _candado:
            _ejecutar("UPDATE codigos_2fa SET codigo_hash = NULL, enviado_en = NULL, envios = envios - 1 "
                      "WHERE reto = %s", (_huella(reto),))
        raise ErrorSegundoFactor(f"No se pudo enviar el codigo: {e}", 503)
    return enmascarar(direccion)


def registrar_correo_en_reto(reto: str, direccion: str, ahora: datetime | None = None) -> str:
    """Staff sin correo: lo registra en su primer inicio de sesion (solo si aun no tiene uno) y envia el codigo."""
    ahora = ahora or datetime.now()
    direccion = validar_correo(direccion)
    with _candado:
        fila = _leer_reto(reto, ahora)
        usuario = usuario_por_id(fila["usuario_id"])
        if usuario is None:
            raise ErrorSegundoFactor("La cuenta no esta disponible.", 401)
        if correo_de(usuario["id"], usuario["rol"]):
            raise ErrorSegundoFactor("Esta cuenta ya tiene un correo registrado.", 409)
        _guardar_preferencias(usuario["id"], direccion, None)
    return enviar_codigo(reto, ahora)


def verificar(reto: str, codigo: str, ahora: datetime | None = None) -> dict:
    """Comprueba el codigo. Si es correcto lo gasta (uso unico) y devuelve el usuario ya autenticado."""
    ahora = ahora or datetime.now()
    codigo = re.sub(r"\s+", "", str(codigo or ""))
    with _candado:
        fila = _leer_reto(reto, ahora)
        if not fila["codigo_hash"]:
            raise ErrorSegundoFactor("Primero pide el codigo.", 409)
        if fila["codigo_expira"] <= ahora:
            raise ErrorSegundoFactor("El codigo vencio. Pide uno nuevo.", 410)
        if fila["intentos"] >= MAX_INTENTOS_CODIGO:
            raise ErrorSegundoFactor("Demasiados intentos con este codigo. Pide uno nuevo.", 429)
        if not hmac.compare_digest(fila["codigo_hash"], _codigo_hash(reto, codigo)):
            intentos = fila["intentos"] + 1
            if intentos >= MAX_INTENTOS_CODIGO:
                _ejecutar("UPDATE codigos_2fa SET intentos = %s, codigo_hash = NULL WHERE reto = %s",
                          (intentos, _huella(reto)))
                raise ErrorSegundoFactor("Codigo incorrecto. Ya no quedan intentos: pide uno nuevo.", 429)
            _ejecutar("UPDATE codigos_2fa SET intentos = %s WHERE reto = %s", (intentos, _huella(reto)))
            n = MAX_INTENTOS_CODIGO - intentos
            raise ErrorSegundoFactor(f"Codigo incorrecto. Te {'queda' if n == 1 else 'quedan'} {n} "
                                     f"{'intento' if n == 1 else 'intentos'}.", 401)
        _ejecutar("UPDATE codigos_2fa SET usado = 1, codigo_hash = NULL WHERE reto = %s", (_huella(reto),))
        usuario = usuario_por_id(fila["usuario_id"])
    if usuario is None:
        raise ErrorSegundoFactor("La cuenta no esta disponible.", 401)
    return usuario
