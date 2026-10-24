"""
Prueba de caja negra: verifica la descarga del comprobante PDF con DISTINTOS
PEDIDOS y DISTINTOS CLIENTES, contra la API real. Corresponde a la tarea
"Testear la descarga con distintos pedidos y clientes" (HU-16).

Endpoint probado:
  GET /ventas/{id}/comprobante.pdf?rol=...&usuario_id=...&atendido_por=...

Regla de negocio (HU-16 tarea 880): un cliente solo puede descargar el
comprobante de SUS pedidos; admin y cajero pueden descargar cualquiera; una
venta presencial sin dueno se puede descargar libremente.

Para no tocar datos reales, la prueba crea sus propios datos (dos clientes de
prueba, un producto y varias ventas) y los elimina al final por ids exactos.

Casos:
  D1  El cliente dueno descarga su comprobante (200, PDF valido)
  D2  Otro cliente intenta descargar el comprobante ajeno (403)
  D3  Un cliente sin identificar (sin usuario_id) intenta descargarlo (403)
  D4  El cajero descarga el comprobante de un cliente (200)
  D5  El administrador descarga el comprobante de un cliente (200)
  D6  Una venta presencial sin dueno se descarga libremente (200)
  D7  Una venta no finalizada (en progreso) se rechaza (400)
  D8  Una venta inexistente responde 404
  D9  Tres pedidos distintos del mismo cliente generan tres PDFs distintos,
      cada uno con su propio numero y su propio total
  D10 El comprobante de una venta con factura muestra los datos del cliente
      (nombre y documento) y los productos
  D11 El nombre del archivo descargado es el numero del comprobante (CR-aaaa-id)
  D12 Cada cliente solo puede descargar sus propios pedidos (cruce de dos
      clientes con dos pedidos cada uno)

INSTALACION:
    pip install requests mysql-connector-python pypdf

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_descarga_comprobante_pedidos_clientes.py
"""

import io
import os
import re
import time
from datetime import datetime

import mysql.connector
import requests
from pypdf import PdfReader

API_BASE = os.environ.get("API_BASE", "http://localhost:8000")
DB_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "password": "",
    "database": "caja_registradora_ia",
}

PRECIO = 5.00


def db_ejecutar(sql, params=()):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        cursor.execute(sql, params)
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def crear_cliente_usuario(nombre):
    return db_ejecutar(
        "INSERT INTO usuarios (username, password, rol) VALUES (%s, %s, 'cliente')",
        (nombre, "hash_de_prueba_no_valido"),
    )


def crear_producto_prueba(categoria_id):
    return db_ejecutar(
        "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock) "
        "VALUES (%s, %s, %s, %s, %s)",
        ("Producto prueba descarga", PRECIO, categoria_id,
         f"test_desc_{int(time.time() * 1000)}", 1000),
    )


def crear_venta(producto_id, unidades, estado="finalizada", usuario_id=None,
                factura=False, nombre=None, documento=None, cajero="cajero"):
    total = round(unidades * PRECIO, 2)
    venta_id = db_ejecutar(
        "INSERT INTO ventas (estado, total, creado_en, metodo_pago, monto_recibido, cambio, "
        "factura, cliente_nombre, cliente_documento, cliente_tipo_documento, "
        "cliente_usuario_id, cajero) "
        "VALUES (%s, %s, %s, 'efectivo', %s, 0, %s, %s, %s, %s, %s, %s)",
        (estado, total, datetime.now(), total, 1 if factura else 0, nombre, documento,
         "CI" if documento else None, usuario_id, cajero),
    )
    db_ejecutar(
        "INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
        "VALUES (%s, %s, %s, %s)", (venta_id, producto_id, unidades, PRECIO))
    return venta_id, total


def descargar(venta_id, rol=None, usuario_id=None):
    params = {}
    if rol is not None:
        params["rol"] = rol
    if usuario_id is not None:
        params["usuario_id"] = usuario_id
    return requests.get(f"{API_BASE}/ventas/{venta_id}/comprobante.pdf",
                        params=params, timeout=15)


def es_pdf(r):
    return (r.status_code == 200 and r.content[:5] == b"%PDF-"
            and "application/pdf" in r.headers.get("content-type", ""))


def texto_pdf(contenido):
    lector = PdfReader(io.BytesIO(contenido))
    return " ".join(" ".join((p.extract_text() or "").split()) for p in lector.pages)


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

    sufijo = int(time.time()) % 100000
    usuarios, ventas = [], []
    producto_id = crear_producto_prueba(categorias[0]["id"])
    resultados = []
    print(f"Producto de prueba creado (id={producto_id}).")

    try:
        ana = crear_cliente_usuario(f"cliente_ana_{sufijo}")
        beto = crear_cliente_usuario(f"cliente_beto_{sufijo}")
        usuarios += [ana, beto]
        print(f"Clientes de prueba creados (ids {ana} y {beto}).")

        v_ana1, t_ana1 = crear_venta(producto_id, 2, usuario_id=ana, factura=True,
                                     nombre="Ana Torrez Prueba", documento="5551111")
        v_ana2, t_ana2 = crear_venta(producto_id, 3, usuario_id=ana)
        v_ana3, t_ana3 = crear_venta(producto_id, 5, usuario_id=ana)
        v_beto1, t_beto1 = crear_venta(producto_id, 1, usuario_id=beto, factura=True,
                                       nombre="Beto Salazar Prueba", documento="5552222")
        v_beto2, t_beto2 = crear_venta(producto_id, 4, usuario_id=beto)
        v_presencial, _ = crear_venta(producto_id, 2)
        v_progreso, _ = crear_venta(producto_id, 1, estado="en_progreso", usuario_id=ana)
        ventas += [v_ana1, v_ana2, v_ana3, v_beto1, v_beto2, v_presencial, v_progreso]
        print(f"{len(ventas)} ventas de prueba creadas.\n")

        print("--- PERMISOS ---")
        r = descargar(v_ana1, "cliente", ana)
        resultados.append(reporte(
            "D1 El cliente dueno descarga su comprobante", es_pdf(r),
            f"cliente {ana}, venta {v_ana1} | codigo: {r.status_code} | "
            f"tipo: {r.headers.get('content-type')} | {len(r.content) / 1024:.1f} KB"))

        r = descargar(v_ana1, "cliente", beto)
        resultados.append(reporte(
            "D2 Otro cliente no puede descargar el comprobante ajeno",
            r.status_code == 403,
            f"cliente {beto} pide la venta {v_ana1} (de {ana}) | codigo: {r.status_code}"))

        r = descargar(v_ana1, "cliente", None)
        resultados.append(reporte(
            "D3 Un cliente sin identificar (sin usuario_id) recibe 403",
            r.status_code == 403, f"codigo: {r.status_code}"))

        r = descargar(v_ana1, "cajero")
        resultados.append(reporte(
            "D4 El cajero descarga el comprobante de un cliente", es_pdf(r),
            f"codigo: {r.status_code}"))

        r = descargar(v_beto1, "administrador")
        resultados.append(reporte(
            "D5 El administrador descarga el comprobante de un cliente", es_pdf(r),
            f"codigo: {r.status_code}"))

        r = descargar(v_presencial, "cliente", beto)
        resultados.append(reporte(
            "D6 Una venta presencial sin dueno se descarga libremente", es_pdf(r),
            f"venta {v_presencial} sin propietario | codigo: {r.status_code}"))

        r = descargar(v_progreso, "administrador")
        resultados.append(reporte(
            "D7 Una venta no finalizada se rechaza (400)", r.status_code == 400,
            f"venta {v_progreso} en progreso | codigo: {r.status_code}"))

        r = descargar(99999999, "administrador")
        resultados.append(reporte(
            "D8 Una venta inexistente responde 404", r.status_code == 404,
            f"codigo: {r.status_code}"))

        print("\n--- CONTENIDO CON DISTINTOS PEDIDOS Y CLIENTES ---")
        pedidos = [(v_ana1, t_ana1), (v_ana2, t_ana2), (v_ana3, t_ana3)]
        pdfs, ok9, detalles = [], True, []
        for vid, total in pedidos:
            r = descargar(vid, "cliente", ana)
            texto = texto_pdf(r.content) if es_pdf(r) else ""
            numero = f"CR-{datetime.now().year}-{vid:08d}"
            bien = es_pdf(r) and numero in texto and f"Bs. {total:.2f}" in texto
            ok9 = ok9 and bien
            pdfs.append(r.content)
            detalles.append(f"venta {vid}: {numero} / Bs. {total:.2f} -> {'ok' if bien else 'MAL'}")
        distintos = len({hash(c) for c in pdfs}) == len(pdfs)
        resultados.append(reporte(
            "D9 Tres pedidos del mismo cliente generan tres PDFs distintos",
            ok9 and distintos, " | ".join(detalles)))

        r = descargar(v_ana1, "cliente", ana)
        texto = texto_pdf(r.content)
        ok10 = all(x in texto for x in ["Ana Torrez Prueba", "5551111",
                                         "Producto prueba descarga", "Factura", "Solicitada"])
        r_b = descargar(v_beto1, "cliente", beto)
        texto_b = texto_pdf(r_b.content)
        ok10 = ok10 and "Beto Salazar Prueba" in texto_b and "Ana Torrez Prueba" not in texto_b
        resultados.append(reporte(
            "D10 El comprobante con factura muestra los datos del cliente y los productos",
            ok10,
            "Ana: nombre, documento, producto y 'Factura solicitada' presentes | "
            "Beto: su nombre y ninguno de los datos de Ana"))

        r = descargar(v_ana2, "cliente", ana)
        esperado = f"CR-{datetime.now().year}-{v_ana2:08d}.pdf"
        disposicion = r.headers.get("content-disposition", "")
        resultados.append(reporte(
            "D11 El archivo descargado se llama como el numero del comprobante",
            esperado in disposicion, f"esperado: {esperado} | recibido: {disposicion}"))

        cruce = [
            (ana, v_ana1, 200), (ana, v_ana2, 200), (ana, v_beto1, 403), (ana, v_beto2, 403),
            (beto, v_beto1, 200), (beto, v_beto2, 200), (beto, v_ana1, 403), (beto, v_ana3, 403),
        ]
        malos = []
        for usuario, vid, esperado_cod in cruce:
            r = descargar(vid, "cliente", usuario)
            if r.status_code != esperado_cod:
                malos.append((usuario, vid, r.status_code, esperado_cod))
        resultados.append(reporte(
            "D12 Cada cliente solo descarga sus propios pedidos (cruce de 2 clientes)",
            not malos,
            f"combinaciones probadas: {len(cruce)} | incorrectas: {len(malos)}"
            + (f" (ej. {malos[0]})" if malos else "")))
    finally:
        for v in ventas:
            db_ejecutar("DELETE FROM detalle_venta WHERE venta_id = %s", (v,))
            db_ejecutar("DELETE FROM ventas WHERE id = %s", (v,))
        for u in usuarios:
            db_ejecutar("DELETE FROM usuarios WHERE id = %s", (u,))
        db_ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
        print(f"\nDatos de prueba eliminados (producto {producto_id}, "
              f"{len(ventas)} ventas y {len(usuarios)} clientes).")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
