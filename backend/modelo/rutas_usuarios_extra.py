"""
Complemento del CRUD de usuarios (solo administrador). No importa YOLO ni nada de deteccion.

  DELETE /usuarios/{id}            eliminar de verdad (solo si la cuenta no tiene historial)
  GET    /usuarios/correos-2fa     correo del segundo factor de cada usuario (HU-24)
  PUT    /usuarios/{id}/correo-2fa registrar, cambiar o quitar ese correo

Alta, lista, edicion y activar/desactivar ya existen en deteccionobjeto.py (/usuarios).
"""

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

import db
import segundo_factor

router = APIRouter(tags=["usuarios"])

# tablas que referencian a un usuario: (tabla, columna)
_REFERENCIAS = (("clientes", "usuario_id"), ("compras", "usuario_id"), ("ventas", "cliente_usuario_id"))


def _admin(x_usuario_id: int | None) -> int:
    if x_usuario_id is None:
        raise HTTPException(status_code=401, detail="Inicia sesion para continuar.")
    if not db.es_admin_activo(x_usuario_id):
        raise HTTPException(status_code=403, detail="Solo el administrador puede gestionar usuarios.")
    return x_usuario_id


def _una_fila(sql: str, params=()):
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(sql, params)
        return cursor.fetchone()
    finally:
        conexion.close()


def _tiene_historial(usuario_id: int) -> str | None:
    """Nombre de la tabla donde la cuenta ya tiene datos, o None si esta libre."""
    for tabla, columna in _REFERENCIAS:
        try:
            fila = _una_fila(f"SELECT COUNT(*) AS n FROM {tabla} WHERE {columna} = %s", (usuario_id,))
        except Exception:
            continue        # la tabla o la columna no existe en esta base
        if fila and fila["n"]:
            return tabla
    return None


@router.delete("/usuarios/{usuario_id}")
def eliminar_usuario(usuario_id: int, x_usuario_id: int | None = Header(default=None)):
    actor = _admin(x_usuario_id)
    if usuario_id == actor:
        raise HTTPException(status_code=422, detail="No puedes eliminar tu propia cuenta.")
    fila = _una_fila("SELECT id, username, rol, activo FROM usuarios WHERE id = %s", (usuario_id,))
    if fila is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    if fila["rol"] == "administrador" and fila["activo"]:
        otros = _una_fila("SELECT COUNT(*) AS n FROM usuarios WHERE rol = 'administrador' AND activo = 1 AND id <> %s",
                          (usuario_id,))
        if not otros or not otros["n"]:
            raise HTTPException(status_code=422, detail="No puedes eliminar al ultimo administrador activo.")
    if _tiene_historial(usuario_id):
        raise HTTPException(
            status_code=409,
            detail=f'"{fila["username"]}" ya tiene historial (clientes, ventas o compras), por eso no se puede '
                   'eliminar. Desactivalo para que no pueda iniciar sesion.')
    conexion = db._conexion()
    try:
        cursor = conexion.cursor()
        try:
            for tabla in ("codigos_2fa", "segundo_factor_usuario"):
                try:
                    cursor.execute(f"DELETE FROM {tabla} WHERE usuario_id = %s", (usuario_id,))
                except Exception:
                    pass
            try:
                cursor.execute("DELETE FROM intentos_login WHERE usuario = %s", (fila["username"].lower(),))
            except Exception:
                pass
            cursor.execute("DELETE FROM usuarios WHERE id = %s", (usuario_id,))
        except Exception:
            conexion.rollback()
            raise HTTPException(status_code=409, detail=f'"{fila["username"]}" tiene datos relacionados: '
                                                         'desactivalo en vez de eliminarlo.')
        conexion.commit()
    finally:
        conexion.close()
    return {"ok": True, "id": usuario_id}


@router.get("/usuarios/correos-2fa")
def correos_2fa(x_usuario_id: int | None = Header(default=None)):
    _admin(x_usuario_id)
    segundo_factor.asegurar_tablas()
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute("SELECT usuario_id, correo FROM segundo_factor_usuario WHERE correo IS NOT NULL")
        return {str(f["usuario_id"]): f["correo"] for f in cursor.fetchall()}
    finally:
        conexion.close()


class CorreoIn(BaseModel):
    correo: str | None = None      # None o vacio = quitarlo


@router.put("/usuarios/{usuario_id}/correo-2fa")
def fijar_correo_2fa(usuario_id: int, datos: CorreoIn, x_usuario_id: int | None = Header(default=None)):
    _admin(x_usuario_id)
    if _una_fila("SELECT id FROM usuarios WHERE id = %s", (usuario_id,)) is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    texto = (datos.correo or "").strip()
    try:
        correo = segundo_factor.validar_correo(texto) if texto else None
    except segundo_factor.ErrorSegundoFactor as e:
        raise HTTPException(status_code=e.estado, detail=str(e))
    segundo_factor.guardar_correo(usuario_id, correo)
    return {"id": usuario_id, "correo": correo}
