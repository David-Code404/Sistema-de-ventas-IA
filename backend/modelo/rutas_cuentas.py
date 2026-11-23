"""
Inicio de sesion y registro de clientes. No importan YOLO ni nada de deteccion.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import bloqueo_login
import db

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
    if usuario["rol"] == "cliente":
        usuario["cliente"] = db.obtener_cliente_de_usuario(usuario["id"])
    return usuario


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
