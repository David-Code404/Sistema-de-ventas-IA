"""
Prueba de caja negra: verifica la alerta visual de stock bajo reduciendo el
stock de un producto hasta su minimo configurado (y mas alla), contra la API
real. Corresponde a la tarea "Testear la alerta reduciendo el stock hasta el
minimo configurado" (HU-21_1150).

La alerta de la pantalla de venta (StockBajoBanner) consulta cada 10 s:
  - GET  /inventario/stock-bajo        productos activos con stock <= stock_minimo
El stock se reduce con:
  - POST /inventario/{id}/disminuir    (Inventario > Restar)
  - PUT  /inventario/{id}              (Inventario > Fijar)
  - POST /pedidos/{id}/listo           (pedido en linea marcado como listo)
  - POST /ventas/{id}/finalizar        (venta cobrada en caja)
El minimo se configura con PUT /productos/{id} (Editar producto).

Para no tocar datos reales, la prueba crea su propio producto (stock 10,
minimo 5), una cuenta de cliente y ventas/pedidos de prueba, y los elimina al
final (solo por sus ids exactos).

Casos:
  A1  Stock 10 > minimo 5: NO aparece en la alerta
  A2  Restar hasta 6 (minimo + 1): todavia NO aparece
  A3  Restar 1 -> stock 5 = minimo: APARECE con su stock y minimo
  A4  Restar 1 -> stock 4 (bajo el minimo): sigue apareciendo
  A5  Restar hasta 0: aparece antes que los productos con stock (agotados primero)
  A6  Restar con stock 0: se rechaza y el stock no queda negativo
  A7  Reponer stock por encima del minimo: desaparece de la alerta
  A8  Cambiar el minimo (Editar producto): 12 aparece, 10 (= stock) aparece, 9 desaparece
  A9  Fijar el stock exactamente en el minimo (Inventario > Fijar): aparece
  A10 Un pedido en linea marcado como listo deja el producto en el minimo: aparece
  A11 Una venta cobrada en caja deja el producto en el minimo: aparece
  A12 Producto desactivado con stock bajo: NO aparece

INSTALACION:
    pip install requests mysql-connector-python python-dotenv

Uso (con MySQL y el backend corriendo en el puerto 8000):
    python test_alerta_stock_minimo.py
"""

import os
import random
import time
from pathlib import Path

import mysql.connector
import requests

try:  # Datos de conexion del backend/.env (HU-17); si no hay, valores de XAMPP
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).resolve().parent.parent / "backend" / ".env")
except ImportError:
    pass

API_BASE = os.environ.get("API_BASE", "http://localhost:8000")
DB_CONFIG = {
    "host": os.environ.get("DB_HOST", "localhost"),
    "port": int(os.environ.get("DB_PORT", "3306")),
    "user": os.environ.get("DB_USER", "root"),
    "password": os.environ.get("DB_PASSWORD", ""),
    "database": os.environ.get("DB_NAME", "caja_registradora_ia"),
}

PRECIO = 4.00
STOCK_INICIAL = 10
MINIMO = 5


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


def alerta():
    """Lista que muestra el banner de stock bajo."""
    r = requests.get(f"{API_BASE}/inventario/stock-bajo", timeout=5)
    r.raise_for_status()
    return r.json()


def en_alerta(producto_id):
    for p in alerta():
        if p["id"] == producto_id:
            return p
    return None


def stock_de(producto_id):
    return db_consultar("SELECT stock FROM productos WHERE id = %s", (producto_id,))[0]["stock"]


def restar(producto_id, cantidad):
    return requests.post(f"{API_BASE}/inventario/{producto_id}/disminuir",
                         json={"cantidad": cantidad}, timeout=5)


def aumentar(producto_id, cantidad):
    return requests.post(f"{API_BASE}/inventario/{producto_id}/aumentar",
                         json={"cantidad": cantidad}, timeout=5)


def fijar(producto_id, stock):
    return requests.put(f"{API_BASE}/inventario/{producto_id}", json={"stock": stock}, timeout=5)


def cambiar_minimo(producto_id, categoria_id, minimo):
    return requests.put(f"{API_BASE}/productos/{producto_id}", json={
        "nombre": "Producto de prueba alerta stock", "precio": PRECIO,
        "categoria_id": categoria_id, "stock_minimo": minimo}, timeout=5)


def describir(producto_id):
    p = en_alerta(producto_id)
    return (f"stock: {stock_de(producto_id)} | minimo: {p['stock_minimo'] if p else '-'} | "
            f"en alerta: {'si' if p else 'no'}")


resultados = []


def reporte(caso, ok, detalle_txt):
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    {detalle_txt}")
    resultados.append((caso, ok, detalle_txt))


def main():
    categorias = requests.get(f"{API_BASE}/categorias", timeout=5).json()
    if not categorias:
        print("Se necesita al menos 1 categoria para correr la prueba.")
        return
    categoria_id = categorias[0]["id"]
    personal = db_consultar(
        "SELECT id FROM usuarios WHERE rol IN ('cajero', 'administrador') ORDER BY rol = 'cajero' DESC LIMIT 1")
    if not personal:
        print("Se necesita un usuario cajero o administrador para correr la prueba.")
        return
    cajero_id = personal[0]["id"]

    producto_id = db_ejecutar(
        "INSERT INTO productos (nombre, precio, categoria_id, clase_modelo, stock, stock_minimo) "
        "VALUES (%s, %s, %s, %s, %s, %s)",
        ("Producto de prueba alerta stock", PRECIO, categoria_id,
         f"test_alerta_{int(time.time() * 1000)}", STOCK_INICIAL, MINIMO))
    ventas_creadas = []
    usuario_cliente = None
    print(f"Producto de prueba creado (id={producto_id}, stock {STOCK_INICIAL}, minimo {MINIMO}).\n")

    try:
        print("--- REDUCIR EL STOCK HASTA EL MINIMO (Inventario > Restar) ---")
        reporte("A1  Stock 10 > minimo 5: NO aparece en la alerta",
                en_alerta(producto_id) is None, describir(producto_id))

        r = restar(producto_id, 4)
        reporte("A2  Restar hasta 6 (minimo + 1): todavia NO aparece",
                r.status_code == 200 and stock_de(producto_id) == 6 and en_alerta(producto_id) is None,
                f"codigo: {r.status_code} | {describir(producto_id)}")

        r = restar(producto_id, 1)
        p = en_alerta(producto_id)
        reporte("A3  Restar 1 -> stock 5 = minimo: APARECE con su stock y minimo",
                r.status_code == 200 and p is not None and p["stock"] == 5 and p["stock_minimo"] == 5,
                f"codigo: {r.status_code} | {describir(producto_id)}")

        r = restar(producto_id, 1)
        p = en_alerta(producto_id)
        reporte("A4  Restar 1 -> stock 4 (bajo el minimo): sigue apareciendo",
                r.status_code == 200 and p is not None and p["stock"] == 4,
                f"codigo: {r.status_code} | {describir(producto_id)}")

        r = restar(producto_id, 4)
        lista = alerta()
        pos = next((i for i, x in enumerate(lista) if x["id"] == producto_id), None)
        antes_con_stock = [x for x in lista[:pos or 0] if x["stock"] > 0]
        reporte("A5  Restar hasta 0: aparece antes que los productos con stock (agotados primero)",
                r.status_code == 200 and pos is not None and lista[pos]["stock"] == 0 and not antes_con_stock,
                f"codigo: {r.status_code} | posicion en la alerta: {pos} de {len(lista)} | "
                f"productos con stock antes que el: {len(antes_con_stock)}")

        r = restar(producto_id, 1)
        reporte("A6  Restar con stock 0: se rechaza y el stock no queda negativo",
                r.status_code == 400 and stock_de(producto_id) == 0,
                f"codigo: {r.status_code} | mensaje: {r.json().get('detail')} | stock: {stock_de(producto_id)}")

        print("\n--- REPONER Y CAMBIAR EL MINIMO ---")
        r = aumentar(producto_id, 10)
        reporte("A7  Reponer stock por encima del minimo (0 -> 10): desaparece de la alerta",
                r.status_code == 200 and en_alerta(producto_id) is None,
                f"codigo: {r.status_code} | {describir(producto_id)}")

        r12 = cambiar_minimo(producto_id, categoria_id, 12)
        con_12 = en_alerta(producto_id) is not None
        r10 = cambiar_minimo(producto_id, categoria_id, 10)
        con_10 = en_alerta(producto_id) is not None
        r9 = cambiar_minimo(producto_id, categoria_id, 9)
        con_9 = en_alerta(producto_id) is not None
        reporte("A8  Cambiar el minimo con stock 10: 12 aparece, 10 (= stock) aparece, 9 desaparece",
                all(x.status_code == 200 for x in (r12, r10, r9)) and con_12 and con_10 and not con_9,
                f"codigos: {r12.status_code}/{r10.status_code}/{r9.status_code} | "
                f"minimo 12: {'si' if con_12 else 'no'} | minimo 10: {'si' if con_10 else 'no'} | "
                f"minimo 9: {'si' if con_9 else 'no'}")
        cambiar_minimo(producto_id, categoria_id, MINIMO)

        r = fijar(producto_id, MINIMO)
        reporte("A9  Fijar el stock exactamente en el minimo (Inventario > Fijar): aparece",
                r.status_code == 200 and en_alerta(producto_id) is not None,
                f"codigo: {r.status_code} | {describir(producto_id)}")

        print("\n--- OTRAS FORMAS DE REDUCIR EL STOCK ---")
        fijar(producto_id, 8)
        sufijo = random.randint(100000, 999999)
        r = requests.post(f"{API_BASE}/auth/registro", json={
            "email": f"alerta{sufijo}@prueba.com", "password": "prueba123",
            "nombre": "Cliente Prueba Alerta", "tipo_documento": "CI",
            "documento": f"9{sufijo}", "telefono": "70000099"}, timeout=10)
        if r.status_code == 201:
            usuario_cliente = r.json()["id"]
            rp = requests.post(f"{API_BASE}/pedidos", json={
                "usuario_id": usuario_cliente,
                "items": [{"producto_id": producto_id, "cantidad": 3}]}, timeout=10)
            pedido_id = rp.json().get("pedido_id") if rp.status_code == 201 else None
            if pedido_id:
                ventas_creadas.append(pedido_id)
            sin_alerta_antes = en_alerta(producto_id) is None
            rl = requests.post(f"{API_BASE}/pedidos/{pedido_id}/listo",
                               json={"usuario_id": cajero_id}, timeout=10)
            reporte("A10 Un pedido en linea marcado como listo deja el producto en el minimo: aparece",
                    rp.status_code == 201 and sin_alerta_antes and rl.status_code == 200
                    and stock_de(producto_id) == 5 and en_alerta(producto_id) is not None,
                    f"pedido: {rp.status_code} | listo: {rl.status_code} | antes en alerta: "
                    f"{'no' if sin_alerta_antes else 'si'} | {describir(producto_id)}")
        else:
            reporte("A10 Un pedido en linea marcado como listo deja el producto en el minimo: aparece",
                    False, f"no se pudo crear la cuenta de cliente: {r.status_code} {r.text[:80]}")

        fijar(producto_id, 6)
        venta_id = requests.post(f"{API_BASE}/ventas/nueva", timeout=5).json()["venta_id"]
        ventas_creadas.append(venta_id)
        db_ejecutar("INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
                    "VALUES (%s, %s, 1, %s)", (venta_id, producto_id, PRECIO))
        db_ejecutar("UPDATE ventas SET total = %s WHERE id = %s", (PRECIO, venta_id))
        rf = requests.post(f"{API_BASE}/ventas/{venta_id}/finalizar", json={
            "metodo_pago": "efectivo", "monto_recibido": PRECIO}, timeout=10)
        reporte("A11 Una venta cobrada en caja (stock 6, vende 1) deja el producto en el minimo: aparece",
                rf.status_code == 200 and stock_de(producto_id) == 5 and en_alerta(producto_id) is not None,
                f"cobro: {rf.status_code} | {describir(producto_id)}")

        fijar(producto_id, 2)
        requests.delete(f"{API_BASE}/productos/{producto_id}", timeout=5)
        reporte("A12 Producto desactivado con stock bajo (2 <= 5): NO aparece",
                en_alerta(producto_id) is None,
                f"activo: {db_consultar('SELECT activo FROM productos WHERE id = %s', (producto_id,))[0]['activo']} | "
                f"{describir(producto_id)}")

    finally:
        for v in ventas_creadas:
            db_ejecutar("DELETE FROM detalle_venta WHERE venta_id = %s", (v,))
            db_ejecutar("DELETE FROM ventas WHERE id = %s", (v,))
        if usuario_cliente:
            db_ejecutar("DELETE FROM clientes WHERE usuario_id = %s", (usuario_cliente,))
            db_ejecutar("DELETE FROM usuarios WHERE id = %s", (usuario_cliente,))
        db_ejecutar("DELETE FROM detalle_venta WHERE producto_id = %s", (producto_id,))
        db_ejecutar("DELETE FROM productos WHERE id = %s", (producto_id,))
        print(f"\nDatos de prueba eliminados (producto {producto_id}, ventas {ventas_creadas}, "
              f"cliente {usuario_cliente}).")

    aprobados = sum(1 for _, ok, _ in resultados if ok)
    print("\n" + "=" * 50)
    print(f"RESUMEN: {aprobados}/{len(resultados)} casos aprobados")


if __name__ == "__main__":
    main()
