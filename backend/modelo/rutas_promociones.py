"""
HU-26 - Tarea 1430: rutas del panel de promociones (solo administrador).
No importa YOLO ni nada de deteccion.

    GET   /promociones/ofertas                      ofertas de hoy (publica, 1440)
    GET   /promociones?usuario_id=1                 lista todas
    POST  /promociones?usuario_id=1                 crea una
    PUT   /promociones/{id}?usuario_id=1            edita una
    PATCH /promociones/{id}/estado?usuario_id=1     activa / desactiva
    POST  /promociones/desactivar-vencidas?usuario_id=1   revisa vencidas ya (1460)

HU-26 1460: al arrancar el backend se inicia un hilo que desactiva las
promociones vencidas al momento y luego cada 10 minutos.
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

import promociones

router = APIRouter(tags=["promociones"])

# HU-26 1460: revision automatica de promociones vencidas mientras el backend corre
router.add_event_handler("startup", promociones.iniciar_revision_automatica)
router.add_event_handler("shutdown", promociones.detener_revision_automatica)


def _exigir_admin(usuario_id: int):
    if not promociones.es_administrador(usuario_id):
        raise HTTPException(
            status_code=403,
            detail="Solo el administrador puede gestionar promociones.",
        )


def _ejecutar(funcion, *args):
    """Traduce los errores de promociones.py a respuestas HTTP."""
    try:
        return funcion(*args)
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@router.get("/promociones/ofertas")
def ofertas_vigentes():
    """
    PUBLICA (tarea 1440): productos con descuento HOY, con precio original y
    precio de oferta. La usa el catalogo del cliente.
    """
    return promociones.ofertas_vigentes()


@router.get("/promociones")
def listar_promociones(usuario_id: int = Query(...)):
    _exigir_admin(usuario_id)
    return promociones.listar_promociones()


@router.post("/promociones", status_code=201)
def crear_promocion(datos: promociones.PromocionIn, usuario_id: int = Query(...)):
    _exigir_admin(usuario_id)
    return _ejecutar(promociones.crear_promocion, datos.model_dump())


@router.put("/promociones/{promocion_id}")
def editar_promocion(
    promocion_id: int, datos: promociones.PromocionIn, usuario_id: int = Query(...)
):
    _exigir_admin(usuario_id)
    return _ejecutar(promociones.actualizar_promocion, promocion_id, datos.model_dump())


class EstadoIn(BaseModel):
    activa: bool


@router.patch("/promociones/{promocion_id}/estado")
def cambiar_estado(promocion_id: int, datos: EstadoIn, usuario_id: int = Query(...)):
    _exigir_admin(usuario_id)
    return _ejecutar(promociones.cambiar_estado_promocion, promocion_id, datos.activa)


@router.post("/promociones/desactivar-vencidas")
def desactivar_vencidas(usuario_id: int = Query(...)):
    """HU-26 1460: desactiva ya las promociones vencidas (sin esperar al hilo)."""
    _exigir_admin(usuario_id)
    desactivadas = promociones.desactivar_vencidas()
    return {"desactivadas": len(desactivadas), "promociones": desactivadas}