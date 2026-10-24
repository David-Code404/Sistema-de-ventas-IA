"""
Prueba de caja negra: verifica (1) las validaciones de datos de producto e
inventario y (2) que los cambios se reflejen de inmediato en el catalogo y
el inventario, contra la API real. Corresponde a la tarea
"Testear validaciones de datos y reflejo inmediato en el catalogo".

Para no tocar productos reales, la prueba crea UN producto de prueba
directamente en la base (el registro por API exige videos) y lo elimina
al final, pase lo que pase.

Casos de validacion (reglas implementadas en deteccionobjeto.py):
  V1  Editar producto con nombre vacio            -> 422
  V2  Editar producto con nombre solo espacios    -> 422
  V3  Editar producto con precio 0                -> 422
  V4  Editar producto con precio negativo         -> 422
  V5  Editar producto con categoria inexistente   -> error 4xx
  V6  Aumentar stock con cantidad 0               -> 422
  V7  Aumentar stock con cantidad negativa        -> 422
  V8  Aumentar stock de producto inexistente      -> 404
  V9  Registrar producto con cantidad negativa    -> 422
  V10 Registrar producto con precio 0             -> 422
  V11 Registrar producto con nombre vacio         -> 422
  V12 Editar producto con datos validos           -> 200

Casos de reflejo inmediato (se lee justo despues de escribir, sin esperas):
  R1  Producto nuevo aparece en el catalogo (GET /productos)
  R2  Editar nombre y precio se ve en el catalogo
  R3  Cambiar la categoria se ve en el catalogo
  R4  Aumentar stock se ve en el inventario (GET /inventario)
  R5  Desactivar el producto lo quita del catalogo y del inventario

INSTALACION:
    pip install requests mysql-connector-python

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_validaciones_producto_catalogo.py
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

NOMBRE_PRUEBA = "Producto de prueba automatizada"
NOMBRE_EDITADO = "Producto de prueba editado"
PRECIO_INICIAL = 5.00
PRECIO_EDITADO = 7.50
STOCK_INICIAL = 10
INCREMENTO_STOCK = 7
ID_INEXISTENTE = 999999


def crear_producto_prueba(categoria_id):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock) "
            "VALUES (%s, %s, %s, %s, %s)",
            (
                NOMBRE_PRUEBA,
                PRECIO_INICIAL,
                categoria_id,
                f"test_auto_{int(time.time())}",
                STOCK_INICIAL,
            ),
        )
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def eliminar_producto_prueba(producto_id):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        cursor.execute("DELETE FROM productos WHERE id = %s", (producto_id,))
        conexion.commit()
    finally:
        conexion.close()


def editar(producto_id, nombre, precio, categoria_id):
    return requests.put(
        f"{API_BASE}/productos/{producto_id}",
        json={"nombre": nombre, "precio": precio, "categoria_id": categoria_id},
        timeout=5,
    )


def aumentar(producto_id, cantidad):
    return requests.post(
        f"{API_BASE}/inventario/{producto_id}/aumentar",
        json={"cantidad": cantidad},
        timeout=5,
    )


def registrar(nombre, precio, categoria_id, cantidad):
    videos = {
        "video_frontal": ("frontal.mp4", b"0", "video/mp4"),
        "video_trasero": ("trasero.mp4", b"0", "video/mp4"),
    }
    return requests.post(
        f"{API_BASE}/registro/producto",
        data={
            "nombre": nombre,
            "precio": precio,
            "categoria_id": categoria_id,
            "cantidad": cantidad,
        },
        files=videos,
        timeout=10,
    )


def catalogo_item(producto_id):
    lista = requests.get(f"{API_BASE}/productos", timeout=5).json()
    for p in lista:
        if p["id"] == producto_id:
            return p
    return None


def inventario_item(producto_id):
    lista = requests.get(f"{API_BASE}/inventario", timeout=5).json()
    for p in lista:
        if p["id"] == producto_id:
            return p
    return None


def reporte_estado(caso, esperado, respuesta):
    obtenido = respuesta.status_code
    ok = obtenido in esperado if isinstance(esperado, tuple) else obtenido == esperado
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    esperado: {esperado} | obtenido: {obtenido}")
    if not ok:
        print(f"    cuerpo de la respuesta: {respuesta.text[:200]}")
    return ok


def reporte_reflejo(caso, ok, detalle, ms):
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    {detalle} | lectura inmediata en {ms:.0f} ms")
    return ok


def main():
    categorias = requests.get(f"{API_BASE}/categorias", timeout=5).json()
    if len(categorias) < 2:
        print("Se necesitan al menos 2 categorias para correr la prueba.")
        return
    cat_a, cat_b = categorias[0], categorias[1]

    producto_id = crear_producto_prueba(cat_a["id"])
    print(f"Producto de prueba creado (id={producto_id}).\n")
    resultados = []

    try:
        print("--- VALIDACIONES DE DATOS ---")
        resultados.append(reporte_estado(
            "V1 Editar con nombre vacio debe rechazarse", 422,
            editar(producto_id, "", PRECIO_INICIAL, cat_a["id"])))
        resultados.append(reporte_estado(
            "V2 Editar con nombre solo espacios debe rechazarse", 422,
            editar(producto_id, "   ", PRECIO_INICIAL, cat_a["id"])))
        resultados.append(reporte_estado(
            "V3 Editar con precio 0 debe rechazarse", 422,
            editar(producto_id, NOMBRE_PRUEBA, 0, cat_a["id"])))
        resultados.append(reporte_estado(
            "V4 Editar con precio negativo debe rechazarse", 422,
            editar(producto_id, NOMBRE_PRUEBA, -5, cat_a["id"])))
        resultados.append(reporte_estado(
            "V5 Editar con categoria inexistente debe rechazarse",
            (400, 404, 409, 422),
            editar(producto_id, NOMBRE_PRUEBA, PRECIO_INICIAL, ID_INEXISTENTE)))
        resultados.append(reporte_estado(
            "V6 Aumentar stock con cantidad 0 debe rechazarse", 422,
            aumentar(producto_id, 0)))
        resultados.append(reporte_estado(
            "V7 Aumentar stock con cantidad negativa debe rechazarse", 422,
            aumentar(producto_id, -3)))
        resultados.append(reporte_estado(
            "V8 Aumentar stock de producto inexistente debe dar 404", 404,
            aumentar(ID_INEXISTENTE, 1)))
        resultados.append(reporte_estado(
            "V9 Registrar con cantidad negativa debe rechazarse", 422,
            registrar(NOMBRE_PRUEBA, 5, cat_a["id"], -1)))
        resultados.append(reporte_estado(
            "V10 Registrar con precio 0 debe rechazarse", 422,
            registrar(NOMBRE_PRUEBA, 0, cat_a["id"], 1)))
        resultados.append(reporte_estado(
            "V11 Registrar con nombre vacio debe rechazarse", 422,
            registrar("", 5, cat_a["id"], 1)))
        resultados.append(reporte_estado(
            "V12 Editar con datos validos debe aceptarse", 200,
            editar(producto_id, NOMBRE_PRUEBA, PRECIO_INICIAL, cat_a["id"])))

        print("\n--- REFLEJO INMEDIATO EN EL CATALOGO ---")
        t0 = time.perf_counter()
        item = catalogo_item(producto_id)
        ms = (time.perf_counter() - t0) * 1000
        resultados.append(reporte_reflejo(
            "R1 Producto nuevo aparece en el catalogo",
            item is not None and item["nombre"] == NOMBRE_PRUEBA,
            f"nombre en catalogo: {item['nombre'] if item else None}", ms))

        editar(producto_id, NOMBRE_EDITADO, PRECIO_EDITADO, cat_a["id"])
        t0 = time.perf_counter()
        item = catalogo_item(producto_id)
        ms = (time.perf_counter() - t0) * 1000
        ok = (item is not None and item["nombre"] == NOMBRE_EDITADO
              and float(item["precio"]) == PRECIO_EDITADO)
        resultados.append(reporte_reflejo(
            "R2 Editar nombre y precio se ve en el catalogo", ok,
            f"en catalogo: {item['nombre'] if item else None} / "
            f"Bs. {item['precio'] if item else None}", ms))

        editar(producto_id, NOMBRE_EDITADO, PRECIO_EDITADO, cat_b["id"])
        t0 = time.perf_counter()
        item = catalogo_item(producto_id)
        ms = (time.perf_counter() - t0) * 1000
        ok = item is not None and item["categoria_nombre"] == cat_b["nombre"]
        resultados.append(reporte_reflejo(
            "R3 Cambiar la categoria se ve en el catalogo", ok,
            f"categoria en catalogo: {item['categoria_nombre'] if item else None}", ms))

        aumentar(producto_id, INCREMENTO_STOCK)
        t0 = time.perf_counter()
        item = inventario_item(producto_id)
        ms = (time.perf_counter() - t0) * 1000
        esperado = STOCK_INICIAL + INCREMENTO_STOCK
        ok = item is not None and item["stock"] == esperado
        resultados.append(reporte_reflejo(
            "R4 Aumentar stock se ve en el inventario", ok,
            f"stock esperado {esperado}, en inventario: "
            f"{item['stock'] if item else None}", ms))

        requests.delete(f"{API_BASE}/productos/{producto_id}", timeout=5)
        t0 = time.perf_counter()
        en_catalogo = catalogo_item(producto_id)
        en_inventario = inventario_item(producto_id)
        ms = (time.perf_counter() - t0) * 1000
        ok = en_catalogo is None and en_inventario is None
        resultados.append(reporte_reflejo(
            "R5 Desactivar el producto lo quita del catalogo e inventario", ok,
            f"en catalogo: {en_catalogo is not None} | "
            f"en inventario: {en_inventario is not None}", ms))
    finally:
        eliminar_producto_prueba(producto_id)
        print(f"\nProducto de prueba (id={producto_id}) eliminado.")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
