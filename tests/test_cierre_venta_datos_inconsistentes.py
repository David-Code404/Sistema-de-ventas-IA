"""
Prueba de caja negra: cierre de venta con datos inconsistentes.

Flujo real de la API (segun /docs):
    POST /ventas/nueva                                       -> {"venta_id": N}
    POST /ventas/{venta_id}/items/{producto_id}/incrementar  -> agrega 1 unidad
    POST /ventas/{venta_id}/finalizar                        -> body:
        {"metodo_pago": str, "monto_recibido": num, "pago_confirmado": bool}

Casos probados:
  1. Finalizar venta inexistente                    -> 404
  2. Finalizar venta vacia (sin items)              -> 400/409/422
  3. Incrementar item en venta inexistente          -> 404
  4. Incrementar producto inexistente               -> 404/422
  5. Sobrepasar stock al agregar items              -> 400/409/422
  6. Finalizar con metodo_pago invalido/vacio       -> 422
  7. Finalizar con monto_recibido negativo          -> 422
  8. Finalizar con monto_recibido insuficiente      -> 400/409/422
  9. Finalizar con pago_confirmado=false            -> 400/409/422
 10. Flujo valido completo                          -> 200/201
"""

import requests

API_BASE = "http://localhost:8000"


# ---------- helpers ----------

def listar_productos():
    return requests.get(f"{API_BASE}/productos", timeout=5)


def nueva_venta():
    return requests.post(f"{API_BASE}/ventas/nueva", timeout=5)


def incrementar_item(venta_id, producto_id):
    return requests.post(
        f"{API_BASE}/ventas/{venta_id}/items/{producto_id}/incrementar",
        timeout=5,
    )


def finalizar_venta(venta_id, metodo_pago="efectivo",
                    monto_recibido=0, pago_confirmado=True):
    return requests.post(
        f"{API_BASE}/ventas/{venta_id}/finalizar",
        json={
            "metodo_pago": metodo_pago,
            "monto_recibido": monto_recibido,
            "pago_confirmado": pago_confirmado,
        },
        timeout=5,
    )


# ---------- reporte ----------

def reporte(caso, esperados, respuesta):
    obtenido = respuesta.status_code
    if isinstance(esperados, int):
        esperados = (esperados,)
    ok = obtenido in esperados
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    esperado: {esperados} | obtenido: {obtenido}")
    if not ok:
        print(f"    cuerpo: {respuesta.text[:200]}")
    return ok


# ---------- utilidades ----------

def obtener_producto_existente():
    r = listar_productos()
    if r.status_code != 200:
        print(f"[ABORTADO] GET /productos respondio {r.status_code}")
        return None
    data = r.json()
    if isinstance(data, list):
        items = data
    else:
        items = (data.get("items")
                 or data.get("productos")
                 or data.get("data")
                 or [])
    return items[0] if items else None


def venta_id_de(respuesta):
    try:
        j = respuesta.json()
    except Exception:
        return None
    return j.get("venta_id") or j.get("id")


def preparar_venta_con_item(producto_id, veces=1):
    """Crea una venta nueva y agrega el producto indicado 'veces' veces.
    Devuelve el venta_id o None si algo fallo."""
    r = nueva_venta()
    if r.status_code not in (200, 201):
        return None
    vid = venta_id_de(r)
    for _ in range(veces):
        r_inc = incrementar_item(vid, producto_id)
        if r_inc.status_code >= 400:
            return None
    return vid


# ---------- casos ----------

def main():
    resultados = []

    # ---------- preparacion ----------
    producto = obtener_producto_existente()
    if not producto:
        print("[ABORTADO] No hay productos en la BD para usar como referencia.")
        return

    producto_id = producto.get("id") or producto.get("producto_id")
    precio = (producto.get("precio")
              or producto.get("precio_unitario")
              or producto.get("precio_venta")
              or 0)
    stock_disponible = (producto.get("stock")
                        or producto.get("stock_actual")
                        or producto.get("cantidad")
                        or 0)
    print(f"Producto de referencia id={producto_id}, "
          f"precio={precio}, stock={stock_disponible}\n")

    # ---------- Caso 1: finalizar venta inexistente ----------
    r = finalizar_venta(999999)
    resultados.append(reporte("Finalizar venta inexistente", (404,), r))

    # ---------- Caso 2: finalizar venta vacia ----------
    r = nueva_venta()
    if r.status_code in (200, 201):
        vid = venta_id_de(r)
        r2 = finalizar_venta(vid)
        resultados.append(reporte("Finalizar venta sin items",
                                  (400, 409, 422), r2))
    else:
        print(f"[OMITIDO] No se pudo crear venta vacia: {r.status_code}")

    # ---------- Caso 3: incrementar item en venta inexistente ----------
    r = incrementar_item(999999, producto_id)
    resultados.append(reporte("Incrementar item en venta inexistente",
                              (404,), r))

    # ---------- Caso 4: incrementar producto inexistente ----------
    r = nueva_venta()
    if r.status_code in (200, 201):
        vid = venta_id_de(r)
        r2 = incrementar_item(vid, 999999)
        resultados.append(reporte("Incrementar producto inexistente",
                                  (404, 422), r2))
    else:
        print(f"[OMITIDO] No se pudo crear venta para caso 4: {r.status_code}")

    # ---------- Caso 5: sobrepasar stock ----------
    r = nueva_venta()
    if r.status_code in (200, 201):
        vid = venta_id_de(r)
        try:
            stock_int = int(stock_disponible) if stock_disponible else 0
        except (TypeError, ValueError):
            stock_int = 0
        limite = max(stock_int + 5, 5)
        ultima = None
        for _ in range(limite):
            ultima = incrementar_item(vid, producto_id)
            if ultima.status_code >= 400:
                break
        if ultima is not None and ultima.status_code >= 400:
            resultados.append(reporte("Sobrepasar stock al agregar item",
                                      (400, 409, 422), ultima))
        else:
            print("[FALLIDO] Sobrepasar stock: la API permitio agregar mas "
                  "unidades que el stock sin rechazar")
            resultados.append(False)
    else:
        print(f"[OMITIDO] No se pudo crear venta para caso 5: {r.status_code}")

    # ---------- Caso 6: metodo_pago invalido/vacio ----------
    vid = preparar_venta_con_item(producto_id, veces=1)
    if vid is not None:
        r = finalizar_venta(vid, metodo_pago="",
                            monto_recibido=999999, pago_confirmado=True)
        resultados.append(reporte("Finalizar con metodo_pago vacio",
                                  (400, 422), r))
    else:
        print("[OMITIDO] No se pudo preparar venta para caso 6")

    # ---------- Caso 7: monto_recibido negativo ----------
    vid = preparar_venta_con_item(producto_id, veces=1)
    if vid is not None:
        r = finalizar_venta(vid, metodo_pago="efectivo",
                            monto_recibido=-100, pago_confirmado=True)
        resultados.append(reporte("Finalizar con monto_recibido negativo",
                                  (400, 422), r))
    else:
        print("[OMITIDO] No se pudo preparar venta para caso 7")

    # ---------- Caso 8: monto_recibido insuficiente ----------
    vid = preparar_venta_con_item(producto_id, veces=2)
    if vid is not None:
        r = finalizar_venta(vid, metodo_pago="efectivo",
                            monto_recibido=0, pago_confirmado=True)
        resultados.append(reporte("Finalizar con monto insuficiente",
                                  (400, 409, 422), r))
    else:
        print("[OMITIDO] No se pudo preparar venta para caso 8")

    # ---------- Caso 9: pago_confirmado=false ----------
    vid = preparar_venta_con_item(producto_id, veces=1)
    if vid is not None:
        r = finalizar_venta(vid, metodo_pago="efectivo",
                            monto_recibido=999999, pago_confirmado=False)
        resultados.append(reporte("Finalizar con pago_confirmado=false",
                                  (400, 409, 422), r))
    else:
        print("[OMITIDO] No se pudo preparar venta para caso 9")

    # ---------- Caso 10: flujo valido ----------
    vid = preparar_venta_con_item(producto_id, veces=1)
    if vid is not None:
        r = finalizar_venta(vid, metodo_pago="efectivo",
                            monto_recibido=999999, pago_confirmado=True)
        resultados.append(reporte(
            "Flujo valido (nueva -> incrementar -> finalizar)",
            (200, 201), r))
    else:
        print("[OMITIDO] No se pudo preparar venta para caso 10")

    # ---------- resumen ----------
    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()