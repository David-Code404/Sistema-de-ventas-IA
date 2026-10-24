"""
Prueba de caja negra: verifica el autocompletado de los datos del cliente en la
factura (busqueda por CI) con clientes NUEVOS y clientes HABITUALES, contra la
API real. Corresponde a la tarea "Testear el autocompletado con clientes nuevos
y habituales" (HU-14).

El autocompletado de la pantalla de cobro usa dos endpoints:
  - GET  /clientes/{documento}        busca al cliente por su documento
  - POST /ventas/{id}/finalizar       al cobrar, registra o actualiza al cliente

Para no tocar datos reales, la prueba crea sus propios clientes, un producto y
ventas de prueba, y los elimina al final (solo por sus ids exactos).

Clientes habituales (el documento ya existe):
  H1  La busqueda devuelve todos sus datos (nombre, tipo, correo, telefono, direccion)
  H2  Si el cajero edita los datos al cobrar, el cliente queda actualizado
  H3  Si deja campos vacios, NO se borran los datos que ya tenia
  H4  Cada compra suma 1 a total_compras
  H5  La venta guarda los datos editados (los de la factura)

Clientes nuevos (el documento no existe):
  N1  La busqueda responde 404 "Cliente no encontrado"
  N2  Al cobrar con factura queda registrado con sus datos
  N3  En la siguiente busqueda ya aparece (se autocompleta) con total_compras = 1
  N4  Una venta sin documento NO crea ningun cliente
  N5  Documento con formato invalido: se rechaza y no se crea el cliente
  N6  Factura sin nombre: se rechaza y no se crea el cliente

INSTALACION:
    pip install requests mysql-connector-python

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_autocompletado_clientes.py
"""

import os
import random
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


def db_ejecutar(sql, params=()):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        cursor.execute(sql, params)
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def db_consultar(sql, params=()):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(sql, params)
        return cursor.fetchall()
    finally:
        conexion.close()


def documento_libre():
    """CI de 7 digitos que no exista todavia en la tabla clientes."""
    while True:
        doc = str(random.randint(8000000, 8999999))
        if not db_consultar("SELECT id FROM clientes WHERE documento = %s", (doc,)):
            return doc


def crear_producto_prueba(categoria_id):
    return db_ejecutar(
        "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock) "
        "VALUES (%s, %s, %s, %s, %s)",
        ("Producto de prueba autocompletado", PRECIO_PRODUCTO, categoria_id,
         f"test_auto_{int(time.time() * 1000)}", 100),
    )


def nueva_venta(producto_id):
    """Crea una venta abierta con 1 unidad del producto de prueba."""
    venta_id = requests.post(f"{API_BASE}/ventas/nueva", timeout=5).json()["venta_id"]
    db_ejecutar(
        "INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
        "VALUES (%s, %s, 1, %s)", (venta_id, producto_id, PRECIO_PRODUCTO))
    db_ejecutar("UPDATE ventas SET total = %s WHERE id = %s", (PRECIO_PRODUCTO, venta_id))
    return venta_id


def cobrar(venta_id, **cliente):
    """Finaliza la venta en efectivo con los datos de cliente indicados."""
    cuerpo = {"metodo_pago": "efectivo", "monto_recibido": 100}
    cuerpo.update(cliente)
    return requests.post(f"{API_BASE}/ventas/{venta_id}/finalizar", json=cuerpo, timeout=5)


def buscar(documento):
    return requests.get(f"{API_BASE}/clientes/{documento}", timeout=5)


def fila_cliente(documento):
    filas = db_consultar("SELECT * FROM clientes WHERE documento = %s", (documento,))
    return filas[0] if filas else None


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
    documentos_prueba = []
    resultados = []
    print(f"Producto de prueba creado (id={producto_id}).\n")

    try:
        # ── Clientes habituales ─────────────────────────────────
        print("--- CLIENTES HABITUALES ---")
        doc_h = documento_libre()
        documentos_prueba.append(doc_h)
        db_ejecutar(
            "INSERT INTO clientes (documento, tipo_documento, nombre, email, telefono, "
            "direccion, total_compras) VALUES (%s, 'CI', %s, %s, %s, %s, 3)",
            (doc_h, "Cliente Habitual Prueba", "habitual@prueba.com",
             "70000001", "Calle Original 100"))

        r = buscar(doc_h)
        d = r.json() if r.status_code == 200 else {}
        ok = (r.status_code == 200 and d.get("nombre") == "Cliente Habitual Prueba"
              and d.get("tipo_documento") == "CI" and d.get("email") == "habitual@prueba.com"
              and d.get("telefono") == "70000001" and d.get("direccion") == "Calle Original 100")
        resultados.append(reporte(
            "H1 La busqueda devuelve todos los datos del cliente habitual", ok,
            f"codigo: {r.status_code} | nombre: {d.get('nombre')} | correo: {d.get('email')} "
            f"| telefono: {d.get('telefono')} | direccion: {d.get('direccion')}"))

        venta_h = nueva_venta(producto_id)
        ventas_creadas.append(venta_h)
        r = cobrar(
            venta_h, factura=True, cliente_documento=doc_h, cliente_tipo_documento="CI",
            cliente_nombre="Cliente Habitual Editado", cliente_email="editado@prueba.com",
            cliente_telefono="70000002", cliente_direccion="Calle Nueva 200")
        c = fila_cliente(doc_h)
        ok = (r.status_code == 200 and c["nombre"] == "Cliente Habitual Editado"
              and c["email"] == "editado@prueba.com" and c["telefono"] == "70000002"
              and c["direccion"] == "Calle Nueva 200")
        resultados.append(reporte(
            "H2 Editar los datos al cobrar actualiza al cliente habitual", ok,
            f"codigo: {r.status_code} | nombre: {c['nombre']} | correo: {c['email']} "
            f"| telefono: {c['telefono']} | direccion: {c['direccion']}"))

        v = db_consultar("SELECT * FROM ventas WHERE id = %s", (venta_h,))[0]
        ok = (v["factura"] == 1 and v["cliente_documento"] == doc_h
              and v["cliente_nombre"] == "Cliente Habitual Editado"
              and v["cliente_email"] == "editado@prueba.com"
              and v["cliente_direccion"] == "Calle Nueva 200")
        resultados.append(reporte(
            "H5 La venta guarda los datos editados (los de la factura)", ok,
            f"factura: {v['factura']} | documento: {v['cliente_documento']} "
            f"| nombre: {v['cliente_nombre']} | direccion: {v['cliente_direccion']}"))

        ok = c["total_compras"] == 4
        resultados.append(reporte(
            "H4 Cada compra suma 1 a total_compras (de 3 a 4)", ok,
            f"total_compras despues de la compra: {c['total_compras']}"))

        venta_h2 = nueva_venta(producto_id)
        ventas_creadas.append(venta_h2)
        r = cobrar(
            venta_h2, factura=True, cliente_documento=doc_h, cliente_tipo_documento="CI",
            cliente_nombre="Cliente Habitual Editado")
        c2 = fila_cliente(doc_h)
        ok = (r.status_code == 200 and c2["email"] == "editado@prueba.com"
              and c2["telefono"] == "70000002" and c2["direccion"] == "Calle Nueva 200"
              and c2["total_compras"] == 5)
        resultados.append(reporte(
            "H3 Dejar campos vacios al cobrar NO borra los datos que ya tenia", ok,
            f"codigo: {r.status_code} | correo: {c2['email']} | telefono: {c2['telefono']} "
            f"| direccion: {c2['direccion']} | total_compras: {c2['total_compras']}"))

        # ── Clientes nuevos ─────────────────────────────────────
        print("\n--- CLIENTES NUEVOS ---")
        doc_n = documento_libre()
        documentos_prueba.append(doc_n)
        r = buscar(doc_n)
        resultados.append(reporte(
            "N1 Buscar un documento que no existe responde 404", r.status_code == 404,
            f"codigo: {r.status_code} | mensaje: {r.json().get('detail') if r.status_code == 404 else '-'}"))

        venta_n = nueva_venta(producto_id)
        ventas_creadas.append(venta_n)
        r = cobrar(
            venta_n, factura=True, cliente_documento=doc_n, cliente_tipo_documento="CI",
            cliente_nombre="Cliente Nuevo Prueba", cliente_email="nuevo@prueba.com",
            cliente_telefono="71111111", cliente_direccion="Av. Nueva 300")
        c = fila_cliente(doc_n)
        ok = (r.status_code == 200 and c is not None and c["nombre"] == "Cliente Nuevo Prueba"
              and c["email"] == "nuevo@prueba.com" and c["telefono"] == "71111111"
              and c["direccion"] == "Av. Nueva 300")
        resultados.append(reporte(
            "N2 Cobrar con factura registra al cliente nuevo con sus datos", ok,
            f"codigo: {r.status_code} | registrado: {c is not None}"
            + (f" | nombre: {c['nombre']} | correo: {c['email']}" if c else "")))

        r = buscar(doc_n)
        d = r.json() if r.status_code == 200 else {}
        ok = (r.status_code == 200 and d.get("nombre") == "Cliente Nuevo Prueba"
              and d.get("direccion") == "Av. Nueva 300" and d.get("total_compras") == 1)
        resultados.append(reporte(
            "N3 La siguiente busqueda ya lo autocompleta (ahora es habitual)", ok,
            f"codigo: {r.status_code} | nombre: {d.get('nombre')} "
            f"| total_compras: {d.get('total_compras')}"))

        antes = db_consultar("SELECT COUNT(*) AS n FROM clientes")[0]["n"]
        venta_s = nueva_venta(producto_id)
        ventas_creadas.append(venta_s)
        r = cobrar(venta_s)
        despues = db_consultar("SELECT COUNT(*) AS n FROM clientes")[0]["n"]
        resultados.append(reporte(
            "N4 Una venta sin documento no crea ningun cliente",
            r.status_code == 200 and antes == despues,
            f"codigo: {r.status_code} | clientes antes: {antes} | despues: {despues}"))

        doc_i = "12AB"
        documentos_prueba.append(doc_i)
        venta_i = nueva_venta(producto_id)
        ventas_creadas.append(venta_i)
        r = cobrar(venta_i, factura=True, cliente_documento=doc_i,
                   cliente_tipo_documento="CI", cliente_nombre="Documento Invalido")
        ok = 400 <= r.status_code < 500 and fila_cliente(doc_i) is None
        resultados.append(reporte(
            "N5 Documento con formato invalido se rechaza y no crea el cliente", ok,
            f"codigo: {r.status_code} | cliente creado: {fila_cliente(doc_i) is not None}"))

        doc_s = documento_libre()
        documentos_prueba.append(doc_s)
        venta_sn = nueva_venta(producto_id)
        ventas_creadas.append(venta_sn)
        r = cobrar(venta_sn, factura=True, cliente_documento=doc_s,
                   cliente_tipo_documento="CI")
        ok = 400 <= r.status_code < 500 and fila_cliente(doc_s) is None
        resultados.append(reporte(
            "N6 Factura sin nombre se rechaza y no crea el cliente", ok,
            f"codigo: {r.status_code} | cliente creado: {fila_cliente(doc_s) is not None}"))
    finally:
        for v in ventas_creadas:
            db_ejecutar("DELETE FROM detalle_venta WHERE venta_id = %s", (v,))
            db_ejecutar("DELETE FROM ventas WHERE id = %s", (v,))
        for doc in documentos_prueba:
            db_ejecutar("DELETE FROM clientes WHERE documento = %s", (doc,))
        db_ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
        print(f"\nDatos de prueba eliminados (producto {producto_id}, "
              f"{len(ventas_creadas)} ventas y {len(documentos_prueba)} clientes).")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
