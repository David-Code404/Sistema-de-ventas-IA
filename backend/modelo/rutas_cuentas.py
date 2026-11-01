"""
Inicio de sesion y registro de clientes. No importan YOLO ni nada de deteccion.
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import db
import seguridad

router = APIRouter(tags=["cuentas"])


class LoginIn(BaseModel):
    username: str  # usuario del personal o correo del cliente
    password: str


@router.post("/auth/login")
def login(datos: LoginIn):
    usuario = db.login_usuario(datos.username, datos.password)
    if usuario is None:
        raise HTTPException(status_code=401, detail="Usuario o contrasena incorrectos.")
    # Con la verificacion en dos pasos activada, falta el segundo paso (/auth/2fa/verificar)
    if db.dosfa_activo(usuario["id"]):
        return {"requiere_2fa": True, "username": usuario["username"],
                "token_2fa": seguridad.crear_token_2fa(usuario["id"])}
    if usuario["rol"] == "cliente":
        usuario["cliente"] = db.obtener_cliente_de_usuario(usuario["id"])
    usuario["token"] = seguridad.crear_token(usuario)
    return usuario


class CambiarPasswordIn(BaseModel):
    usuario_id:      int
    password_actual: str
    password_nueva:  str


@router.post("/auth/cambiar-password")
def cambiar_password(datos: CambiarPasswordIn, request: Request):
    """Cambia la contraseña del usuario confirmando la actual (cualquier rol)."""
    if request.state.usuario["id"] != datos.usuario_id:
        raise HTTPException(status_code=403, detail="Solo puedes cambiar tu propia contraseña.")
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
        nuevo = db.registrar_cliente(
            email=datos.email,
            password=datos.password,
            nombre=datos.nombre,
            tipo_documento=datos.tipo_documento,
            documento=datos.documento,
            telefono=datos.telefono,
            direccion=datos.direccion,
        )
        nuevo["token"] = seguridad.crear_token(nuevo)
        return nuevo
    except ValueError as e:
        mensaje = str(e)
        codigo = 409 if "registrad" in mensaje or "ya tiene una cuenta" in mensaje else 422
        raise HTTPException(status_code=codigo, detail=mensaje)
