"""
Verificacion en dos pasos (TOTP). No importa YOLO ni nada de deteccion.

  GET  /auth/2fa/estado       ¿la tiene activada la persona con sesion?
  POST /auth/2fa/preparar     genera el secreto y el QR (todavia no queda activa)
  POST /auth/2fa/activar      confirma con un codigo de la app y entrega los codigos de respaldo
  POST /auth/2fa/desactivar   la apaga (pide la contrasena y un codigo)
  POST /auth/2fa/verificar    segundo paso del inicio de sesion (publica)
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import db
import seguridad

router = APIRouter(tags=["dos pasos"])


def _usuario(request: Request) -> dict:
    return request.state.usuario


@router.get("/auth/2fa/estado")
def estado(request: Request):
    u = _usuario(request)
    datos = db.dosfa_datos(u["id"]) or {}
    return {"activo": bool(datos.get("totp_activo")),
            "codigos_respaldo_restantes": len(datos.get("respaldo") or [])}


@router.post("/auth/2fa/preparar")
def preparar(request: Request):
    u = _usuario(request)
    datos = db.dosfa_datos(u["id"])
    if datos is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    if datos["totp_activo"]:
        raise HTTPException(status_code=409, detail="La verificacion en dos pasos ya esta activada.")
    secreto = seguridad.nuevo_secreto()
    db.dosfa_guardar_pendiente(u["id"], secreto)
    return {"secreto": secreto, "uri": seguridad.uri_totp(secreto, datos["username"])}


class CodigoIn(BaseModel):
    codigo: str


@router.post("/auth/2fa/activar")
def activar(datos_in: CodigoIn, request: Request):
    u = _usuario(request)
    datos = db.dosfa_datos(u["id"])
    if datos is None or not datos["totp_secret"]:
        raise HTTPException(status_code=409, detail="Primero genera el codigo QR.")
    if datos["totp_activo"]:
        raise HTTPException(status_code=409, detail="La verificacion en dos pasos ya esta activada.")
    clave = f"activar:{u['id']}"
    if seguridad.hay_bloqueo(clave):
        raise HTTPException(status_code=429, detail="Demasiados intentos. Espera unos minutos.")
    if not seguridad.codigo_valido(datos["totp_secret"], datos_in.codigo):
        seguridad.registrar_fallo(clave)
        raise HTTPException(status_code=422, detail="El codigo no es correcto. Revisa que la hora del celular sea automatica.")
    seguridad.limpiar_fallos(clave)
    codigos = seguridad.generar_codigos_respaldo()
    db.dosfa_activar(u["id"], [seguridad.hash_codigo(c) for c in codigos])
    return {"activo": True, "codigos_respaldo": codigos}


class DesactivarIn(BaseModel):
    password: str
    codigo: str


def _codigo_o_respaldo(datos: dict, codigo: str) -> bool:
    if seguridad.codigo_valido(datos["totp_secret"], codigo):
        return True
    return db.dosfa_usar_respaldo(datos["id"], seguridad.hash_codigo(codigo))


@router.post("/auth/2fa/desactivar")
def desactivar(datos_in: DesactivarIn, request: Request):
    u = _usuario(request)
    datos = db.dosfa_datos(u["id"])
    if datos is None or not datos["totp_activo"]:
        raise HTTPException(status_code=409, detail="La verificacion en dos pasos no esta activada.")
    clave = f"desactivar:{u['id']}"
    if seguridad.hay_bloqueo(clave):
        raise HTTPException(status_code=429, detail="Demasiados intentos. Espera unos minutos.")
    if db.login_usuario(datos["username"], datos_in.password) is None:
        seguridad.registrar_fallo(clave)
        raise HTTPException(status_code=401, detail="La contrasena es incorrecta.")
    if not _codigo_o_respaldo(datos, datos_in.codigo):
        seguridad.registrar_fallo(clave)
        raise HTTPException(status_code=422, detail="El codigo no es correcto.")
    seguridad.limpiar_fallos(clave)
    db.dosfa_desactivar(u["id"])
    return {"activo": False}


class VerificarIn(BaseModel):
    token_2fa: str
    codigo: str


@router.post("/auth/2fa/verificar")
def verificar(datos_in: VerificarIn):
    """Segundo paso del inicio de sesion: canjea el token temporal + el codigo por la sesion."""
    token = seguridad.leer_token(datos_in.token_2fa, "2fa")
    if token is None:
        raise HTTPException(status_code=401, detail="El tiempo para verificar se acabo. Inicia sesion de nuevo.")
    usuario_id = int(token["sub"])
    clave = f"login:{usuario_id}"
    if seguridad.hay_bloqueo(clave):
        raise HTTPException(status_code=429, detail="Demasiados intentos. Espera unos minutos.")
    datos = db.dosfa_datos(usuario_id)
    if datos is None or not datos["totp_activo"]:
        raise HTTPException(status_code=401, detail="Inicia sesion de nuevo.")
    if not _codigo_o_respaldo(datos, datos_in.codigo):
        seguridad.registrar_fallo(clave)
        raise HTTPException(status_code=401, detail="El codigo no es correcto.")
    seguridad.limpiar_fallos(clave)
    usuario = {"id": datos["id"], "username": datos["username"], "rol": datos["rol"]}
    if usuario["rol"] == "cliente":
        usuario["cliente"] = db.obtener_cliente_de_usuario(usuario["id"])
    usuario["token"] = seguridad.crear_token(usuario)
    return usuario
