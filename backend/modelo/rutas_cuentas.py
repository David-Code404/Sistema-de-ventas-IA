"""
Inicio de sesion y registro de clientes. No importan YOLO ni nada de deteccion.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import bloqueo_login
import db
import segundo_factor

router = APIRouter(tags=["cuentas"])


class LoginIn(BaseModel):
    username: str  # usuario del personal o correo del cliente
    password: str


def _bloqueado(segundos: int) -> HTTPException:
    return HTTPException(status_code=429, detail=bloqueo_login.mensaje_bloqueo(segundos),
                         headers={"Retry-After": str(segundos)})


@router.post("/auth/login")
def login(datos: LoginIn):
    # HU-24 1320: tras 3 intentos fallidos el usuario queda bloqueado unos minutos
    segundos = bloqueo_login.segundos_de_bloqueo(datos.username)
    if segundos > 0:
        raise _bloqueado(segundos)
    usuario = db.login_usuario(datos.username, datos.password)
    if usuario is None:
        fallo = bloqueo_login.registrar_fallo(datos.username)
        if fallo["bloqueado"]:
            raise _bloqueado(fallo["segundos"])
        n = fallo["intentos_restantes"]
        raise HTTPException(
            status_code=401,
            detail=f"Usuario o contrasena incorrectos. Te {'queda' if n == 1 else 'quedan'} {n} "
                   f"{'intento' if n == 1 else 'intentos'} antes de un bloqueo temporal.")
    bloqueo_login.registrar_exito(datos.username)
    # HU-24 1310/1330: administrador y cajero siempre, cliente si lo activo -> falta el codigo del correo
    if segundo_factor.requiere(usuario):
        reto = segundo_factor.crear_reto(usuario["id"])
        direccion = segundo_factor.correo_de(usuario["id"], usuario["rol"])
        if not direccion:
            return {"requiere_2fa": True, "reto": reto, "falta_correo": True}
        try:
            enmascarado = segundo_factor.enviar_codigo(reto)
        except segundo_factor.ErrorSegundoFactor as e:
            raise HTTPException(status_code=e.estado, detail=str(e))
        return {"requiere_2fa": True, "reto": reto, "falta_correo": False, "correo": enmascarado}
    if usuario["rol"] == "cliente":
        usuario["cliente"] = db.obtener_cliente_de_usuario(usuario["id"])
    return usuario


def _error_2fa(e: "segundo_factor.ErrorSegundoFactor") -> HTTPException:
    return HTTPException(status_code=e.estado, detail=str(e))


class RetoIn(BaseModel):
    reto: str


class CorreoRetoIn(RetoIn):
    correo: str


class CodigoIn(RetoIn):
    codigo: str


@router.post("/auth/2fa/correo")
def registrar_correo_2fa(datos: CorreoRetoIn):
    """Primer inicio de sesion de un administrador/cajero sin correo: lo registra y envia el codigo."""
    try:
        return {"correo": segundo_factor.registrar_correo_en_reto(datos.reto, datos.correo)}
    except segundo_factor.ErrorSegundoFactor as e:
        raise _error_2fa(e)


@router.post("/auth/2fa/reenviar")
def reenviar_codigo_2fa(datos: RetoIn):
    try:
        return {"correo": segundo_factor.enviar_codigo(datos.reto)}
    except segundo_factor.ErrorSegundoFactor as e:
        raise _error_2fa(e)


@router.post("/auth/2fa/verificar")
def verificar_codigo_2fa(datos: CodigoIn):
    """Si el codigo es correcto devuelve el usuario, igual que /auth/login sin segundo factor."""
    try:
        return segundo_factor.verificar(datos.reto, datos.codigo)
    except segundo_factor.ErrorSegundoFactor as e:
        raise _error_2fa(e)


@router.get("/auth/2fa/estado")
def estado_2fa(usuario_id: int):
    usuario = segundo_factor.usuario_por_id(usuario_id)
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    return segundo_factor.estado(usuario_id, usuario["rol"])


class ConfigurarSegundoFactorIn(BaseModel):
    usuario_id: int
    password:   str                 # confirma que es el dueño de la cuenta
    activo:     bool | None = None  # solo clientes
    correo:     str | None = None


@router.put("/auth/2fa/configuracion")
def configurar_2fa(datos: ConfigurarSegundoFactorIn):
    """Activa/desactiva el segundo factor (cliente) o cambia el correo (cualquier rol). Pide la contrasena."""
    usuario = segundo_factor.usuario_por_id(datos.usuario_id)
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    segundos = bloqueo_login.segundos_de_bloqueo(usuario["username"])
    if segundos > 0:
        raise _bloqueado(segundos)
    if db.login_usuario(usuario["username"], datos.password) is None:
        fallo = bloqueo_login.registrar_fallo(usuario["username"])
        if fallo["bloqueado"]:
            raise _bloqueado(fallo["segundos"])
        raise HTTPException(status_code=401, detail="Contrasena incorrecta.")
    try:
        return segundo_factor.configurar(datos.usuario_id, usuario["rol"], datos.activo, datos.correo)
    except segundo_factor.ErrorSegundoFactor as e:
        raise _error_2fa(e)


class CambiarPasswordIn(BaseModel):
    usuario_id:      int
    password_actual: str
    password_nueva:  str


@router.post("/auth/cambiar-password")
def cambiar_password(datos: CambiarPasswordIn):
    """Cambia la contraseña del usuario confirmando la actual (cualquier rol)."""
    try:
        db.cambiar_password(datos.usuario_id, datos.password_actual, datos.password_nueva)
    except db.ContrasenaActualIncorrecta as e:
        raise HTTPException(status_code=401, detail=str(e))
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    return {"ok": True, "mensaje": "Contraseña actualizada."}


class RegistroClienteIn(BaseModel):
    email:          str
    password:       str
    nombre:         str
    tipo_documento: str = "CI"
    documento:      str
    telefono:       str
    direccion:      str | None = None


@router.post("/auth/registro", status_code=201)
def registrar_cliente(datos: RegistroClienteIn):
    """Crea la cuenta de un cliente. Solo crea rol 'cliente'."""
    try:
        return db.registrar_cliente(
            email=datos.email,
            password=datos.password,
            nombre=datos.nombre,
            tipo_documento=datos.tipo_documento,
            documento=datos.documento,
            telefono=datos.telefono,
            direccion=datos.direccion,
        )
    except ValueError as e:
        mensaje = str(e)
        codigo = 409 if "registrad" in mensaje or "ya tiene una cuenta" in mensaje else 422
        raise HTTPException(status_code=codigo, detail=mensaje)
