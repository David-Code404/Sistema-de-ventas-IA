"""
Rutas de lectura del catalogo en linea. No importan YOLO ni nada de deteccion,
para poder desplegarlas solas en la nube (ver app_tienda.py).
"""

from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

import config
import db

router = APIRouter(tags=["tienda"])

IMAGENES_DIR = Path(config.IMAGENES_DIR)


@router.get("/productos")
def buscar_productos(
    nombre:       str | None   = None,
    precio_min:   float | None = None,
    precio_max:   float | None = None,
    categoria_id: int | None   = None,
):
    return db.buscar_productos(
        nombre=nombre,
        precio_min=precio_min,
        precio_max=precio_max,
        categoria_id=categoria_id,
    )


@router.get("/inventario")
def listar_inventario():
    return db.listar_inventario()


@router.get("/inventario/stock-bajo")
def listar_stock_bajo():
    """Productos que alcanzaron su stock minimo (para la alerta del cajero)."""
    return db.listar_stock_bajo()


@router.get("/productos/{producto_id}/imagen")
def obtener_imagen_producto(producto_id: int):
    for ext in [".jpg", ".jpeg", ".png", ".webp"]:
        ruta = IMAGENES_DIR / f"{producto_id}{ext}"
        if ruta.exists():
            return FileResponse(str(ruta))
    raise HTTPException(status_code=404, detail="Sin imagen")


@router.get("/categorias")
def listar_categorias():
    return db.listar_categorias()
