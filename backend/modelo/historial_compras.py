"""
HU-25 - Tarea 1400: Historial de compras por proveedor (solo lectura).

Lee las tablas que crean las tareas 1350 (modelo Proveedor y Compra) y
1390 (registro de compras con actualizacion de stock). Este modulo NO crea
ni modifica nada: si el companero de la 1350 uso otros nombres de tabla o
de columna, solo hay que ajustar las consultas SQL de este archivo.

Esquema que se espera:
    proveedores    (id, razon_social, nit, telefono, correo, direccion, activo)
    compras        (id, proveedor_id, creado_en)
    detalle_compra (id, compra_id, producto_id, cantidad, costo_unitario)
"""

from datetime import date, datetime, time, timedelta
from decimal import Decimal

import db


def es_administrador(usuario_id: int) -> bool:
    """True si el usuario existe y tiene rol administrador."""
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute("SELECT rol FROM usuarios WHERE id = %s", (usuario_id,))
        fila = cursor.fetchone()
        return fila is not None and fila["rol"] == "administrador"
    finally:
        conexion.close()


def _a_float(valor):
    if valor is None:
        return 0.0
    return float(valor) if isinstance(valor, Decimal) else float(valor)


def _a_iso(valor):
    return valor.isoformat() if hasattr(valor, "isoformat") else valor


def historial_compras_proveedor(
    proveedor_id: int,
    desde: date | None = None,
    hasta: date | None = None,
) -> dict:
    """
    Devuelve los datos del proveedor, un resumen y la lista de sus compras
    (de la mas reciente a la mas antigua), cada una con sus productos.

    `desde` y `hasta` son opcionales e incluyen el dia completo.
    Lanza LookupError si el proveedor no existe y ValueError si el rango
    de fechas no es valido.
    """
    if desde and hasta and desde > hasta:
        raise ValueError("La fecha 'desde' no puede ser posterior a la fecha 'hasta'.")

    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)

        # ── Proveedor ─────────────────────────────────────────
        cursor.execute(
            "SELECT id, razon_social, nit, telefono, correo, direccion, activo "
            "FROM proveedores WHERE id = %s",
            (proveedor_id,),
        )
        proveedor = cursor.fetchone()
        if proveedor is None:
            raise LookupError("Proveedor no encontrado.")
        proveedor["activo"] = bool(proveedor["activo"])

        # ── Compras del periodo ───────────────────────────────
        condiciones = ["c.proveedor_id = %s"]
        parametros = [proveedor_id]
        if desde:
            condiciones.append("c.creado_en >= %s")
            parametros.append(datetime.combine(desde, time.min))
        if hasta:
            condiciones.append("c.creado_en < %s")
            parametros.append(datetime.combine(hasta + timedelta(days=1), time.min))
        where_sql = " AND ".join(condiciones)

        cursor.execute(
            f"""
            SELECT
                c.id,
                c.creado_en                                       AS fecha,
                COUNT(dc.id)                                      AS productos_distintos,
                COALESCE(SUM(dc.cantidad), 0)                     AS unidades,
                COALESCE(SUM(dc.cantidad * dc.costo_unitario), 0) AS total
            FROM compras c
            LEFT JOIN detalle_compra dc ON dc.compra_id = c.id
            WHERE {where_sql}
            GROUP BY c.id, c.creado_en
            ORDER BY c.creado_en DESC, c.id DESC
            """,
            parametros,
        )
        compras = cursor.fetchall()

        # ── Productos de cada compra ──────────────────────────
        por_id = {c["id"]: c for c in compras}
        for c in compras:
            c["items"] = []
        if por_id:
            marcadores = ", ".join(["%s"] * len(por_id))
            cursor.execute(
                f"""
                SELECT
                    dc.compra_id,
                    dc.producto_id,
                    COALESCE(p.nombre, CONCAT('Producto #', dc.producto_id)) AS nombre,
                    dc.cantidad,
                    dc.costo_unitario,
                    dc.cantidad * dc.costo_unitario AS subtotal
                FROM detalle_compra dc
                LEFT JOIN productos p ON p.id = dc.producto_id
                WHERE dc.compra_id IN ({marcadores})
                ORDER BY dc.compra_id, dc.id
                """,
                list(por_id),
            )
            for f in cursor.fetchall():
                por_id[f["compra_id"]]["items"].append({
                    "producto_id":    f["producto_id"],
                    "nombre":         f["nombre"],
                    "cantidad":       int(f["cantidad"]),
                    "costo_unitario": round(_a_float(f["costo_unitario"]), 2),
                    "subtotal":       round(_a_float(f["subtotal"]), 2),
                })

        # ── Formato JSON y resumen ────────────────────────────
        total_comprado = 0.0
        unidades = 0
        for c in compras:
            c["fecha"] = _a_iso(c["fecha"])
            c["total"] = round(_a_float(c["total"]), 2)
            c["unidades"] = int(c["unidades"])
            c["productos_distintos"] = int(c["productos_distintos"])
            total_comprado += c["total"]
            unidades += c["unidades"]

        resumen = {
            "compras":             len(compras),
            "total_comprado":      round(total_comprado, 2),
            "unidades":            unidades,
            "promedio_por_compra": round(total_comprado / len(compras), 2) if compras else 0.0,
            "ultima_compra":       compras[0]["fecha"] if compras else None,
        }

        return {
            "proveedor": proveedor,
            "periodo": {
                "desde": desde.isoformat() if desde else None,
                "hasta": hasta.isoformat() if hasta else None,
            },
            "resumen": resumen,
            "compras": compras,
        }
    finally:
        conexion.close()