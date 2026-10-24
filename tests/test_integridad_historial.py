"""
Prueba de caja negra: verifica la integridad de los datos del historial de
ventas y que una venta ya finalizada NO se pueda editar, contra la API real.
Corresponde a la tarea "Testear integridad y no edicion del historial".

Para no tocar ventas reales, la prueba crea sus propios datos de prueba
(un producto y varias ventas finalizadas) y los elimina al final, pase lo
que pase.

Casos de integridad:
  I1  Una venta finalizada cumple total = suma de los subtotales de su detalle
  I2  Todas las ventas finalizadas del historial real cumplen esa misma regla
  I3  Cambiar el precio de un producto NO altera el precio ni el total de una
      venta ya registrada
  I4  Desactivar un producto vendido NO borra la venta ni su detalle del
      historial

Casos de no edicion (venta ya finalizada):
  N1  Finalizar de nuevo una venta finalizada                -> se rechaza (4xx)
  N2  Aumentar la cantidad de un item de una venta finalizada -> se rechaza (4xx)
                                                                y no cambia el detalle
  N3  Disminuir la cantidad de un item                        -> idem
  N4  Eliminar un item                                        -> idem
  N5  Borrar la venta completa (DELETE /ventas/{id})          -> no existe (404/405)
  N6  Editar la venta completa (PUT /ventas/{id})             -> no existe (404/405)

INSTALACION:
    pip install requests mysql-connector-python

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_integridad_historial.py
"""

import os
import time

import mysql.connector
import requests

API_BASE = os.environ.get("API_BASE", "http://localhost:8000")
DB_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "password": "",
    "database": "caja_registradora_ia",
}

PRECIO_PRODUCTO = 5.00
CANTIDAD_VENTA = 2


def db_ejecutar(sql, params=()):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        cursor.execute(sql, params)
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def crear_producto_prueba(categoria_id):
    return db_ejecutar(
        "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock) "
        "VALUES (%s, %s, %s, %s, %s)",
        (
            "Producto de prueba historial",
            PRECIO_PRODUCTO,
            categoria_id,
            f"test_hist_{int(time.time() * 1000)}",
            100,
        ),
    )


def crear_venta_finalizada(producto_id):
    """Crea una venta con CANTIDAD_VENTA unidades y la finaliza por la API."""
    venta_id = requests.post(f"{API_BASE}/ventas/nueva", timeout=5).json()["venta_id"]
    total = round(PRECIO_PRODUCTO * CANTIDAD_VENTA, 2)
    db_ejecutar(
        "INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
        "VALUES (%s, %s, %s, %s)",
        (venta_id, producto_id, CANTIDAD_VENTA, PRECIO_PRODUCTO),
    )
    db_ejecutar("UPDATE ventas SET total = %s WHERE id = %s", (total, venta_id))
    requests.post(
        f"{API_BASE}/ventas/{venta_id}/finalizar",
        json={"metodo_pago": "efectivo", "monto_recibido": total + 10},
        timeout=5,
    )
    return venta_id


def detalle(venta_id):
    return requests.get(f"{API_BASE}/ventas/{venta_id}/detalle", timeout=5).json()


def instantanea(venta_id):
    d = detalle(venta_id)
    items = [
        (i["producto_id"], i["cantidad"], float(i["precio_unitario"]), float(i["subtotal"]))
        for i in d["items"]
    ]
    return float(d["total"]), items


def suma_subtotales(venta_id):
    total, items = instantanea(venta_id)
    return total, round(sum(i[3] for i in items), 2)


def reporte(caso, ok, detalle_txt):
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    {detalle_txt}")
    return ok


def main():
    categorias = requests.get(f"{API_BASE}/categorias", timeout=5).json()
    if not categorias:
        print("Se necesita al menos 1 categoria para correr la prueba.")
        return

    producto_id = crear_producto_prueba(categorias[0]["id"])
    ventas_creadas = []
    resultados = []
    print(f"Producto de prueba creado (id={producto_id}).\n")

    try:
        venta_base = crear_venta_finalizada(producto_id)
        ventas_creadas.append(venta_base)
        print(f"Venta de prueba finalizada creada (id={venta_base}).\n")

        print("--- INTEGRIDAD DEL HISTORIAL ---")
        total, suma = suma_subtotales(venta_base)
        resultados.append(reporte(
            "I1 Total de la venta = suma de subtotales del detalle",
            total == suma, f"total: {total} | suma de subtotales: {suma}"))

        historial = requests.get(f"{API_BASE}/ventas?limite=500", timeout=10).json()
        finalizadas = [v for v in historial if v["estado"] == "finalizada"
                       and v["id"] not in ventas_creadas]
        incoherentes = []
        for v in finalizadas:
            t, s = suma_subtotales(v["id"])
            if t != s:
                incoherentes.append((v["id"], t, s))
        resultados.append(reporte(
            "I2 Todas las ventas finalizadas del historial real son coherentes",
            not incoherentes,
            f"ventas revisadas: {len(finalizadas)} | incoherentes: {len(incoherentes)}"
            + (f" (ej. venta {incoherentes[0][0]}: total {incoherentes[0][1]} vs suma {incoherentes[0][2]})"
               if incoherentes else "")))

        antes = instantanea(venta_base)
        requests.put(
            f"{API_BASE}/productos/{producto_id}",
            json={"nombre": "Producto de prueba historial",
                  "precio": 99.0, "categoria_id": categorias[0]["id"]},
            timeout=5,
        )
        despues = instantanea(venta_base)
        resultados.append(reporte(
            "I3 Cambiar el precio del producto no altera una venta ya registrada",
            antes == despues,
            f"precio unitario antes: {antes[1][0][2]} | despues: {despues[1][0][2]} "
            f"| total antes: {antes[0]} | despues: {despues[0]}"))

        requests.delete(f"{API_BASE}/productos/{producto_id}", timeout=5)
        ids_historial = [v["id"] for v in requests.get(f"{API_BASE}/ventas?limite=500", timeout=10).json()]
        det = instantanea(venta_base)
        resultados.append(reporte(
            "I4 Desactivar un producto vendido no borra la venta del historial",
            venta_base in ids_historial and len(det[1]) == 1,
            f"venta en historial: {venta_base in ids_historial} | items en detalle: {len(det[1])}"))

        print("\n--- NO EDICION DE VENTAS FINALIZADAS ---")
        r = requests.post(
            f"{API_BASE}/ventas/{venta_base}/finalizar",
            json={"metodo_pago": "efectivo", "monto_recibido": 100}, timeout=5)
        resultados.append(reporte(
            "N1 Finalizar de nuevo una venta finalizada se rechaza",
            400 <= r.status_code < 500, f"codigo obtenido: {r.status_code}"))

        intentos = [
            ("N2 Aumentar cantidad de un item", "post", "incrementar"),
            ("N3 Disminuir cantidad de un item", "post", "decrementar"),
            ("N4 Eliminar un item", "delete", None),
        ]
        for caso, metodo, accion in intentos:
            venta = crear_venta_finalizada(producto_id)
            ventas_creadas.append(venta)
            antes = instantanea(venta)
            ruta = f"{API_BASE}/ventas/{venta}/items/{producto_id}"
            if accion:
                ruta += f"/{accion}"
            r = requests.request(metodo.upper(), ruta, timeout=5)
            despues = instantanea(venta)
            rechazada = 400 <= r.status_code < 500
            sin_cambios = antes == despues
            resultados.append(reporte(
                f"{caso} de una venta finalizada se rechaza y no cambia el detalle",
                rechazada and sin_cambios,
                f"codigo obtenido: {r.status_code} | total antes: {antes[0]}, "
                f"despues: {despues[0]} | items antes: {len(antes[1])}, despues: {len(despues[1])}"))

        r = requests.delete(f"{API_BASE}/ventas/{venta_base}", timeout=5)
        resultados.append(reporte(
            "N5 No existe forma de borrar una venta (DELETE /ventas/{id})",
            r.status_code in (404, 405), f"codigo obtenido: {r.status_code}"))
        r = requests.put(f"{API_BASE}/ventas/{venta_base}", json={"total": 1}, timeout=5)
        resultados.append(reporte(
            "N6 No existe forma de editar una venta (PUT /ventas/{id})",
            r.status_code in (404, 405), f"codigo obtenido: {r.status_code}"))
    finally:
        for v in ventas_creadas:
            db_ejecutar("DELETE FROM detalle_venta WHERE venta_id = %s", (v,))
            db_ejecutar("DELETE FROM ventas WHERE id = %s", (v,))
        db_ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
        print(f"\nDatos de prueba eliminados (producto {producto_id} y "
              f"{len(ventas_creadas)} ventas).")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
