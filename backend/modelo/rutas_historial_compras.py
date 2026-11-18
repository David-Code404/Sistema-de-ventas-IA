"""
HU-25 - Tarea 1400: ruta del historial de compras por proveedor.
Solo el administrador puede consultarla. No importa YOLO ni nada de deteccion.
"""

from datetime import date

from fastapi import APIRouter, HTTPException, Query

import historial_compras

router = APIRouter(tags=["proveedores"])


@router.get("/proveedores/{proveedor_id}/historial-compras")
def historial_compras_proveedor(
    proveedor_id: int,
    usuario_id: int = Query(..., description="Id del usuario que consulta (debe ser administrador)"),
    desde: date | None = Query(None, description="Fecha inicial AAAA-MM-DD (incluida)"),
    hasta: date | None = Query(None, description="Fecha final AAAA-MM-DD (incluida)"),
):
    """Compras hechas a un proveedor, con resumen y detalle de productos."""
    if not historial_compras.es_administrador(usuario_id):
        raise HTTPException(
            status_code=403,
            detail="Solo el administrador puede ver el historial de compras.",
        )
    try:
        return historial_compras.historial_compras_proveedor(proveedor_id, desde, hasta)
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))