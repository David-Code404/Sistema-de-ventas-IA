"""
Prueba de caja negra: verifica la exportacion a PDF del historial de ventas con
MAS DE 100 REGISTROS, contra la API real. Corresponde a la tarea "Testear la
exportacion a PDF con mas de 100 registros" (HU-15).

Para no tocar ventas reales, la prueba crea sus propios datos (un producto y
120 ventas finalizadas con productos, cajero y fechas distintas), exporta el PDF
con POST /ventas/historial.pdf pasando solo los ids de prueba, lo analiza y al
final elimina todo por ids exactos, pase lo que pase.

Casos:
  P1  La exportacion responde 200 y devuelve un PDF valido (application/pdf)
  P2  El PDF incluye las 120 ventas (las 120 aparecen en el documento)
  P3  El encabezado indica la cantidad correcta de ventas (120)
  P4  El PDF se reparte en varias paginas (no se corta ni se pierden filas)
  P5  El encabezado con el nombre del negocio y la fecha de generacion se
      repite en TODAS las paginas
  P6  Cada pagina lleva su numero de pagina en el pie (Pagina 1 ... Pagina N)
  P7  El total general del encabezado es igual a la suma de los totales
  P8  Los datos de una venta concreta (fecha, hora, producto, cantidad, total,
      metodo de pago y cajero) salen correctos
  P9  Una venta NO finalizada (en progreso) no aparece en el PDF
  P10 La exportacion tarda menos de 10 segundos
  P11 Exportar solo un subconjunto de ids (10 ventas) incluye solo esas 10

INSTALACION:
    pip install requests mysql-connector-python pypdf

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_exportacion_pdf_mas_de_100.py
"""

import io
import os
import re
import time
from datetime import datetime, timedelta

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

CANTIDAD_VENTAS = 120
PRECIO_PRODUCTO = 4.50
CAJERO = "cajero_prueba"
METODOS = ["efectivo", "tarjeta", "qr"]
NOMBRES_METODO = {"efectivo": "Efectivo", "tarjeta": "Tarjeta", "qr": "QR"}


def db_ejecutar(sql, params=(), muchos=False):
    conexion = mysql.connector.connect(**DB_CONFIG)
    try:
        cursor = conexion.cursor()
        if muchos:
            cursor.executemany(sql, params)
        else:
            cursor.execute(sql, params)
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def crear_producto_prueba(categoria_id):
    return db_ejecutar(
        "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock) "
        "VALUES (%s, %s, %s, %s, %s)",
        ("Producto prueba pdf", PRECIO_PRODUCTO, categoria_id,
         f"test_pdf_{int(time.time() * 1000)}", 1000),
    )


def crear_ventas(producto_id, cantidad, estado="finalizada"):
    """Crea `cantidad` ventas con fecha, cantidad de unidades y metodo distintos."""
    base = datetime(2026, 10, 1, 8, 0, 0)
    ids = []
    for n in range(cantidad):
        unidades = (n % 5) + 1
        total = round(unidades * PRECIO_PRODUCTO, 2)
        metodo = METODOS[n % 3]
        fecha = base + timedelta(hours=n * 3, minutes=n % 60, seconds=n % 60)
        venta_id = db_ejecutar(
            "INSERT INTO ventas (estado, total, creado_en, metodo_pago, cajero) "
            "VALUES (%s, %s, %s, %s, %s)",
            (estado, total, fecha, metodo, CAJERO),
        )
        db_ejecutar(
            "INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
            "VALUES (%s, %s, %s, %s)",
            (venta_id, producto_id, unidades, PRECIO_PRODUCTO),
        )
        ids.append((venta_id, unidades, total, metodo, fecha))
    return ids


def exportar(ids):
    inicio = time.time()
    r = requests.post(f"{API_BASE}/ventas/historial.pdf", json={"ids": ids}, timeout=60)
    return r, round(time.time() - inicio, 2)


def paginas_texto(contenido):
    lector = PdfReader(io.BytesIO(contenido))
    return [p.extract_text() or "" for p in lector.pages]


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
    ventas_ids = []
    resultados = []
    print(f"Producto de prueba creado (id={producto_id}).")

    try:
        datos = crear_ventas(producto_id, CANTIDAD_VENTAS)
        ids = [d[0] for d in datos]
        ventas_ids.extend(ids)
        en_progreso = crear_ventas(producto_id, 1, estado="en_progreso")
        ventas_ids.append(en_progreso[0][0])
        print(f"{len(ids)} ventas finalizadas y 1 en progreso creadas "
              f"(ids {min(ids)} a {max(ids)}).\n")

        r, segundos = exportar(ids)
        es_pdf = r.status_code == 200 and r.content[:5] == b"%PDF-"
        resultados.append(reporte(
            "P1 La exportacion responde 200 y devuelve un PDF valido",
            es_pdf and "application/pdf" in r.headers.get("content-type", ""),
            f"codigo: {r.status_code} | tipo: {r.headers.get('content-type')} "
            f"| tamano: {len(r.content) / 1024:.1f} KB"))
        if not es_pdf:
            return

        paginas = paginas_texto(r.content)
        texto = "\n".join(paginas)

        faltantes = [i for i in ids if not re.search(rf"(?<!\d){i}(?!\d)", texto)]
        resultados.append(reporte(
            f"P2 El PDF incluye las {CANTIDAD_VENTAS} ventas",
            not faltantes,
            f"ventas esperadas: {len(ids)} | ausentes: {len(faltantes)}"
            + (f" (ej. {faltantes[:3]})" if faltantes else "")))

        resultados.append(reporte(
            "P3 El encabezado indica la cantidad correcta de ventas",
            f"{CANTIDAD_VENTAS} venta(s)" in texto,
            f"se busca '{CANTIDAD_VENTAS} venta(s)' en el documento"))

        resultados.append(reporte(
            "P4 El PDF se reparte en varias paginas sin perder filas",
            len(paginas) >= 3 and not faltantes,
            f"paginas generadas: {len(paginas)} para {CANTIDAD_VENTAS} ventas"))

        con_encabezado = sum(1 for t in paginas
                             if "Caja Registradora IA" in t and "Fecha de generacion" in t
                             and re.search(r"\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}", t))
        resultados.append(reporte(
            "P5 Nombre del negocio y fecha de generacion en todas las paginas",
            con_encabezado == len(paginas),
            f"paginas con encabezado: {con_encabezado} de {len(paginas)}"))

        con_numero = sum(1 for n, t in enumerate(paginas, 1) if f"Pagina {n}" in t)
        resultados.append(reporte(
            "P6 Cada pagina lleva su numero de pagina",
            con_numero == len(paginas),
            f"paginas numeradas correctamente: {con_numero} de {len(paginas)}"))

        esperado = round(sum(d[2] for d in datos), 2)
        m = re.search(r"Total general:\s*Bs\.\s*([\d.]+)", texto)
        obtenido = float(m.group(1)) if m else None
        resultados.append(reporte(
            "P7 El total general es igual a la suma de los totales",
            obtenido == esperado,
            f"esperado: Bs. {esperado:.2f} | en el PDF: {obtenido}"))

        vid, unidades, total, metodo, fecha = datos[7]
        lineas = [l.strip() for t in paginas for l in t.splitlines()]
        esperado_fila = [
            str(vid), f"{fecha:%d/%m/%Y}", f"{fecha:%H:%M:%S}",
            f"{unidades} x Producto prueba pdf", f"Bs. {total:.2f}",
            NOMBRES_METODO[metodo], CAJERO,
        ]
        fila = next((lineas[i:i + 7] for i, l in enumerate(lineas)
                     if l == str(vid) and lineas[i + 1:i + 2] == [esperado_fila[1]]), [])
        ok8 = fila == esperado_fila
        resultados.append(reporte(
            "P8 Los datos de una venta salen correctos (fecha, hora, productos, total, metodo, cajero)",
            ok8,
            f"esperado: {' | '.join(esperado_fila)}"
            + ("" if ok8 else f" || en el PDF: {' | '.join(fila) or 'fila no encontrada'}")))

        # P9: venta en progreso no aparece aunque se pida su id
        r2, _ = exportar(ids + [en_progreso[0][0]])
        texto2 = "\n".join(paginas_texto(r2.content))
        resultados.append(reporte(
            "P9 Una venta no finalizada (en progreso) no aparece en el PDF",
            r2.status_code == 200 and f"{CANTIDAD_VENTAS} venta(s)" in texto2,
            f"se pidio la venta {en_progreso[0][0]} (en progreso) | "
            f"ventas en el PDF: {CANTIDAD_VENTAS if f'{CANTIDAD_VENTAS} venta(s)' in texto2 else 'distinto de 120'}"))

        resultados.append(reporte(
            "P10 La exportacion tarda menos de 10 segundos",
            segundos < 10,
            f"tiempo para {CANTIDAD_VENTAS} ventas: {segundos} s"))

        r3, _ = exportar(ids[:10])
        texto3 = "\n".join(paginas_texto(r3.content))
        resultados.append(reporte(
            "P11 Exportar un subconjunto de ids incluye solo esas ventas",
            r3.status_code == 200 and "10 venta(s)" in texto3,
            f"se pidieron 10 ids | encabezado dice 10 venta(s): {'10 venta(s)' in texto3}"))
    finally:
        for v in ventas_ids:
            db_ejecutar("DELETE FROM detalle_venta WHERE venta_id = %s", (v,))
            db_ejecutar("DELETE FROM ventas WHERE id = %s", (v,))
        db_ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
        print(f"\nDatos de prueba eliminados (producto {producto_id} y "
              f"{len(ventas_ids)} ventas).")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
