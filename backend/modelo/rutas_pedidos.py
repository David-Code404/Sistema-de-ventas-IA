"""
Pedidos de clientes en linea (estado 'pendiente', estructura de HU-18_990).
No importan YOLO ni nada de deteccion.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

import db

router = APIRouter(tags=["pedidos"])


class ItemPedidoIn(BaseModel):
    producto_id: int
    cantidad: int


class PedidoIn(BaseModel):
    usuario_id: int
    items: list[ItemPedidoIn]
    nota: str | None = Field(default=None, max_length=255)
    cliente_nombre: str | None = None
    cliente_telefono: str | None = None


@router.post("/pedidos", status_code=201)
def crear_pedido(datos: PedidoIn):
    """Crea el pedido. Solo valida el stock: NO lo descuenta."""
    try:
        return db.crear_pedido(
            datos.usuario_id,
            [i.model_dump() for i in datos.items],
            nota=datos.nota,
            cliente_nombre=datos.cliente_nombre,
            cliente_telefono=datos.cliente_telefono,
        )
    except PermissionError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


def _serializar(pedidos):
    for p in pedidos:
        if hasattr(p["fecha"], "isoformat"):
            p["fecha"] = p["fecha"].isoformat()
        p["total"] = float(p["total"])
    return pedidos


@router.get("/pedidos/pendientes")
def pedidos_pendientes():
    return _serializar(db.listar_pedidos("pendiente"))


@router.get("/pedidos/listos")
def pedidos_listos():
    """Pedidos listos para recoger (ya preparados, stock descontado)."""
    return _serializar(db.listar_pedidos("listo"))


@router.get("/pedidos/resumen")
def resumen_pedidos():
    """Cantidad de pedidos sin finalizar, para el contador del boton Pedidos."""
    return db.resumen_pedidos()


class MarcarListoIn(BaseModel):
    usuario_id: int  # cajero o administrador que preparo el pedido


@router.post("/pedidos/{pedido_id}/listo")
def marcar_listo(pedido_id: int, datos: MarcarListoIn):
    """Marca el pedido como listo para recoger y descuenta el stock."""
    try:
        return db.marcar_pedido_listo(pedido_id, datos.usuario_id)
    except PermissionError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except db.EstadoPedidoInvalido as e:
        raise HTTPException(status_code=409, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
