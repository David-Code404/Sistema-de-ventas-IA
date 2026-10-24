"""
Capa de acceso a la base de datos MySQL (caja_registradora_ia).
"""
import re
import mysql.connector
from mysql.connector import pooling

import config


# ============================================================
# CONFIGURACIÓN MYSQL
# ============================================================

DB_CONFIG = {
    "host": config.DB_HOST,
    "port": config.DB_PORT,
    "user": config.DB_USER,
    "password": config.DB_PASSWORD,
    "database": config.DB_NAME,
}

_pool = pooling.MySQLConnectionPool(
    pool_name="caja_pool",
    pool_size=5,
    **DB_CONFIG,
)


def _conexion():
    return _pool.get_connection()


# ============================================================
# VENTAS
# ============================================================

def crear_venta():
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute("INSERT INTO ventas (estado) VALUES ('en_progreso')")
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def obtener_carrito(venta_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT
                p.id AS producto_id,
                p.nombre,
                dv.cantidad,
                dv.precio_unitario,
                dv.subtotal
            FROM detalle_venta dv
            JOIN productos p ON p.id = dv.producto_id
            WHERE dv.venta_id = %s
            ORDER BY dv.id
            """,
            (venta_id,),
        )
        items = cursor.fetchall()
        cursor.execute("SELECT total FROM ventas WHERE id = %s", (venta_id,))
        fila_total = cursor.fetchone()
        total = (
            float(fila_total["total"])
            if fila_total and fila_total["total"] is not None
            else 0.0
        )
        return {"items": items, "total": total}
    finally:
        conexion.close()


def _recalcular_total(cursor, venta_id):
    cursor.execute(
        """
        UPDATE ventas
        SET total = (
            SELECT COALESCE(SUM(subtotal), 0)
            FROM detalle_venta
            WHERE venta_id = %s
        )
        WHERE id = %s
        """,
        (venta_id, venta_id),
    )


METODOS_PAGO = ("efectivo", "tarjeta", "qr")


def _validar_cliente(
    nombre=None, documento=None, tipo_documento=None,
    email=None, telefono=None, direccion=None,
):
    """Limpia y valida los datos opcionales del cliente. Devuelve tupla normalizada."""
    nom      = (nombre       or "").strip()[:120]
    doc      = (documento    or "").strip()[:20]
    tipo_doc = (tipo_documento or "").strip()[:20]
    mail     = (email        or "").strip()[:120]
    tel      = (telefono     or "").strip()[:20]
    dire     = (direccion    or "").strip()[:150]
    return nom, doc, tipo_doc, mail, tel, dire


def finalizar_venta(
    venta_id, metodo_pago, monto_recibido=None, pago_confirmado=False,
    factura=False, cliente_nombre=None, cliente_documento=None,
    cliente_email=None, cliente_telefono=None, cliente_direccion=None,
    cajero=None, cliente_tipo_documento=None, cliente_usuario_id=None,
):
    if metodo_pago not in METODOS_PAGO:
        raise ValueError("Metodo de pago invalido. Usa: efectivo, tarjeta o qr.")

    nombre, documento, tipo_doc_norm, email, telefono, direccion = _validar_cliente(
        cliente_nombre, cliente_documento, cliente_tipo_documento,
        cliente_email, cliente_telefono, cliente_direccion,
    )

    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT estado, total FROM ventas WHERE id = %s FOR UPDATE",
            (venta_id,),
        )
        venta = cursor.fetchone()
        if venta is None:
            raise LookupError("Venta no encontrada.")
        if venta["estado"] != "en_progreso":
            raise ValueError("La venta ya fue finalizada.")

        total = float(venta["total"])
        if total <= 0:
            raise ValueError("La venta no tiene productos.")

        cambio = None
        if metodo_pago == "efectivo":
            if monto_recibido is None:
                raise ValueError("Ingresa el monto recibido.")
            if round(monto_recibido, 2) < round(total, 2):
                raise ValueError("El monto recibido es menor al total.")
            cambio = round(monto_recibido - total, 2)
        else:
            if not pago_confirmado:
                raise ValueError("El cajero debe confirmar que el pago fue aprobado.")
            monto_recibido = None

        cursor.execute(
            """
            UPDATE ventas
            SET estado = 'finalizada', metodo_pago = %s, monto_recibido = %s, cambio = %s,
                factura = %s, cliente_nombre = %s, cliente_documento = %s,
                cliente_tipo_documento = %s, cliente_email = %s,
                cliente_telefono = %s, cliente_direccion = %s,
                cajero = %s, cliente_usuario_id = %s
            WHERE id = %s
            """,
            (metodo_pago, monto_recibido, cambio, 1 if factura else 0,
             nombre or None, documento or None, tipo_doc_norm or None,
             email or None, telefono or None, direccion or None,
             cajero, cliente_usuario_id, venta_id),
        )
        conexion.commit()
        return {
            "total": total,
            "metodo_pago": metodo_pago,
            "monto_recibido": monto_recibido,
            "cambio": cambio,
        }
    except Exception:
        conexion.rollback()
        raise
    finally:
        conexion.close()


def listar_ventas(limite=50):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT
                v.id,
                v.estado,
                v.total,
                v.creado_en        AS fecha,
                v.metodo_pago,
                u.username         AS cliente_nombre,
                COALESCE(SUM(dv.cantidad), 0) AS cantidad_productos,
                GROUP_CONCAT(
                    CONCAT(dv.cantidad, 'x ', p.nombre)
                    ORDER BY dv.id SEPARATOR ', '
                ) AS resumen_productos
            FROM ventas v
            LEFT JOIN usuarios u      ON u.id  = v.cliente_usuario_id
            LEFT JOIN detalle_venta dv ON dv.venta_id = v.id
            LEFT JOIN productos p     ON p.id  = dv.producto_id
            GROUP BY v.id, v.estado, v.total, v.creado_en, v.metodo_pago, u.username
            ORDER BY v.id DESC
            LIMIT %s
            """,
            (limite,),
        )
        return cursor.fetchall()
    finally:
        conexion.close()


# ============================================================
# PEDIDOS DE CLIENTES (estado 'pendiente')
# ============================================================

def crear_pedido(usuario_id: int, items: list):
    """
    Registra el pedido de un cliente con estado 'pendiente'.
    items: lista de {"producto_id": int, "cantidad": int}.
    El precio de cada producto se toma de la base de datos.
    """
    if not items:
        raise ValueError("El pedido debe tener al menos un producto.")

    # Une las lineas repetidas del mismo producto
    cantidades = {}
    for it in items:
        pid, cant = int(it["producto_id"]), int(it["cantidad"])
        if cant <= 0:
            raise ValueError("Las cantidades deben ser mayores a cero.")
        cantidades[pid] = cantidades.get(pid, 0) + cant

    conexion = _conexion()
    try:
        conexion.autocommit = False
        cursor = conexion.cursor(dictionary=True)

        cursor.execute("SELECT rol FROM usuarios WHERE id = %s", (usuario_id,))
        usuario = cursor.fetchone()
        if usuario is None or usuario["rol"] != "cliente":
            raise LookupError("Cliente no encontrado.")

        total = 0.0
        lineas = []
        for pid, cant in cantidades.items():
            cursor.execute(
                "SELECT nombre, precio, stock FROM productos WHERE id = %s AND activo = TRUE",
                (pid,),
            )
            p = cursor.fetchone()
            if p is None:
                raise LookupError(f"El producto {pid} no existe o no esta disponible.")
            if cant > int(p["stock"]):
                raise ValueError(f"No hay stock suficiente de {p['nombre']} (quedan {p['stock']}).")
            precio = float(p["precio"])
            total += precio * cant
            lineas.append((pid, cant, precio))

        cursor.execute(
            "INSERT INTO ventas (estado, total, cliente_usuario_id) VALUES ('pendiente', %s, %s)",
            (round(total, 2), usuario_id),
        )
        venta_id = cursor.lastrowid
        for pid, cant, precio in lineas:
            cursor.execute(
                "INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario) "
                "VALUES (%s, %s, %s, %s)",
                (venta_id, pid, cant, precio),
            )
        conexion.commit()
        return {"pedido_id": venta_id, "estado": "pendiente", "total": round(total, 2)}
    except Exception:
        conexion.rollback()
        raise
    finally:
        conexion.close()


def listar_pedidos_pendientes():
    """Pedidos de clientes en estado 'pendiente', del mas antiguo al mas reciente."""
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT v.id, v.estado, v.total, v.creado_en AS fecha,
                   u.username AS cliente
            FROM ventas v
            LEFT JOIN usuarios u ON u.id = v.cliente_usuario_id
            WHERE v.estado = 'pendiente'
            ORDER BY v.creado_en ASC, v.id ASC
            """
        )
        pedidos = cursor.fetchall()
        for p in pedidos:
            p["items"] = []
        if pedidos:
            por_id = {p["id"]: p for p in pedidos}
            cursor.execute(
                """
                SELECT dv.venta_id, pr.nombre, dv.cantidad, dv.precio_unitario
                FROM detalle_venta dv
                JOIN productos pr ON pr.id = dv.producto_id
                WHERE dv.venta_id IN (""" + ", ".join(["%s"] * len(por_id)) + """)
                ORDER BY dv.id
                """,
                list(por_id),
            )
            for f in cursor.fetchall():
                por_id[f["venta_id"]]["items"].append({
                    "nombre": f["nombre"],
                    "cantidad": f["cantidad"],
                    "precio_unitario": float(f["precio_unitario"]),
                })
        return pedidos
    finally:
        conexion.close()


def obtener_historial_pdf(ids=None):
    """
    Ventas finalizadas con sus productos, para el PDF del historial.
    Si se pasa `ids`, solo esas ventas; si no, todas. Orden: mas recientes primero.
    """
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        sql = ("SELECT id, creado_en, total, metodo_pago, cajero "
               "FROM ventas WHERE estado = 'finalizada'")
        params = []
        if ids:
            sql += " AND id IN (" + ", ".join(["%s"] * len(ids)) + ")"
            params = list(ids)
        sql += " ORDER BY creado_en DESC, id DESC"
        cursor.execute(sql, params)
        ventas = cursor.fetchall()
        for v in ventas:
            v["items"] = []
        if ventas:
            por_id = {v["id"]: v for v in ventas}
            cursor.execute(
                """
                SELECT dv.venta_id, p.nombre, dv.cantidad
                FROM detalle_venta dv
                JOIN productos p ON p.id = dv.producto_id
                WHERE dv.venta_id IN (""" + ", ".join(["%s"] * len(por_id)) + """)
                ORDER BY dv.id
                """,
                list(por_id),
            )
            for f in cursor.fetchall():
                por_id[f["venta_id"]]["items"].append(
                    {"nombre": f["nombre"], "cantidad": f["cantidad"]})
        return ventas
    finally:
        conexion.close()


def obtener_comprobante(venta_id: int):
    """Devuelve todos los campos necesarios para generar el PDF del comprobante."""
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT
                v.id,
                v.estado,
                v.total,
                v.metodo_pago,
                v.monto_recibido,
                v.cambio,
                v.factura,
                v.cliente_nombre,
                v.cliente_documento,
                v.cliente_tipo_documento,
                v.cliente_email,
                v.cliente_telefono,
                v.cliente_direccion,
                v.cliente_usuario_id,
                v.cajero,
                v.creado_en
            FROM ventas v
            WHERE v.id = %s
            """,
            (venta_id,),
        )
        venta = cursor.fetchone()
        if venta is None:
            return None
        cursor.execute(
            """
            SELECT p.nombre, dv.cantidad, dv.precio_unitario, dv.subtotal
            FROM detalle_venta dv
            JOIN productos p ON p.id = dv.producto_id
            WHERE dv.venta_id = %s
            ORDER BY dv.id
            """,
            (venta_id,),
        )
        venta["items"] = cursor.fetchall()
        return venta
    finally:
        conexion.close()


def verificar_propietario_venta(venta_id: int, usuario_id: int) -> bool:
    """
    Devuelve True si el usuario es el propietario de la venta.
    Devuelve True si la venta no tiene propietario (compra presencial).
    Devuelve False si la venta no existe o pertenece a otro usuario.
    """
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT cliente_usuario_id FROM ventas WHERE id = %s", (venta_id,)
        )
        fila = cursor.fetchone()
        if fila is None:
            return False
        propietario = fila["cliente_usuario_id"]
        if propietario is None:
            return True   # venta sin propietario: acceso libre
        return propietario == usuario_id
    finally:
        conexion.close()


# ============================================================
# CLIENTES
# ============================================================

def guardar_o_actualizar_cliente(
    documento: str,
    tipo_documento: str,
    nombre: str,
    email: str = "",
    telefono: str = "",
    direccion: str = "",
):
    """
    Inserta o actualiza el registro del cliente en la tabla clientes.
    Incrementa total_compras en cada compra.
    """
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            INSERT INTO clientes
                (documento, tipo_documento, nombre, email, telefono, direccion, total_compras)
            VALUES (%s, %s, %s, %s, %s, %s, 1)
            ON DUPLICATE KEY UPDATE
                nombre        = VALUES(nombre),
                email         = COALESCE(NULLIF(VALUES(email),    ''), email),
                telefono      = COALESCE(NULLIF(VALUES(telefono), ''), telefono),
                direccion     = COALESCE(NULLIF(VALUES(direccion),''), direccion),
                total_compras = total_compras + 1
            """,
            (documento, tipo_documento, nombre,
             email or None, telefono or None, direccion or None),
        )
        conexion.commit()
    finally:
        conexion.close()


def buscar_cliente_por_documento(documento: str):
    """Devuelve el dict del cliente o None si no existe."""
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT * FROM clientes WHERE documento = %s", (documento,)
        )
        return cursor.fetchone()
    finally:
        conexion.close()


# ============================================================
# PRODUCTOS
# ============================================================

def obtener_producto_por_clase(clase_modelo):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, nombre, precio FROM productos WHERE clase_modelo = %s AND activo = TRUE",
            (clase_modelo,),
        )
        return cursor.fetchone()
    finally:
        conexion.close()


def buscar_productos(nombre=None, precio_min=None, precio_max=None, categoria_id=None):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        condiciones = ["p.activo = TRUE"]
        parametros = []
        if nombre:
            condiciones.append("p.nombre LIKE %s")
            parametros.append(f"%{nombre}%")
        if precio_min is not None:
            condiciones.append("p.precio >= %s")
            parametros.append(precio_min)
        if precio_max is not None:
            condiciones.append("p.precio <= %s")
            parametros.append(precio_max)
        if categoria_id is not None:
            condiciones.append("p.categoria_id = %s")
            parametros.append(categoria_id)
        where_sql = " AND ".join(condiciones)
        cursor.execute(
            f"""
            SELECT
                p.id,
                p.nombre,
                p.precio,
                p.categoria_id,
                c.nombre AS categoria_nombre,
                p.clase_modelo
            FROM productos p
            LEFT JOIN categorias c ON c.id = p.categoria_id
            WHERE {where_sql}
            ORDER BY p.nombre
            """,
            parametros,
        )
        return cursor.fetchall()
    finally:
        conexion.close()


def asociar_categoria_producto(producto_id, categoria_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE productos SET categoria_id = %s WHERE id = %s",
            (categoria_id, producto_id),
        )
        conexion.commit()
        return cursor.rowcount > 0
    finally:
        conexion.close()


def actualizar_producto(
    producto_id: int,
    nombre: str,
    precio: float,
    categoria_id: int,
    stock_minimo: int = 5,
) -> bool:
    conexion = _conexion()
    try:
        conexion.autocommit = False
        cursor = conexion.cursor()
        cursor.execute(
            """
            UPDATE productos
            SET nombre = %s,
                precio = %s,
                categoria_id = %s,
                stock_minimo = %s
            WHERE id = %s
            """,
            (nombre.strip(), precio, categoria_id, max(0, stock_minimo), producto_id),
        )
        conexion.commit()
        return True
    except Exception as e:
        conexion.rollback()
        print(f"[actualizar_producto] ERROR: {e}")
        raise
    finally:
        conexion.close()


def desactivar_producto(producto_id: int) -> bool:
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE productos SET activo = FALSE WHERE id = %s AND activo = TRUE",
            (producto_id,),
        )
        conexion.commit()
        return cursor.rowcount > 0
    finally:
        conexion.close()


def crear_producto_clip(
    nombre: str,
    precio: float,
    categoria_id: int,
    stock: int = 0,
    stock_minimo: int = 5,
) -> int:
    import time as _time
    base         = nombre.strip().lower().replace(" ", "_")
    clase_modelo = f"{base}_{int(_time.time())}"

    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            INSERT INTO productos
                (nombre, precio, categoria_id, clase_modelo, stock, stock_minimo)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (nombre.strip(), precio, categoria_id, clase_modelo, stock, max(0, stock_minimo)),
        )
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def listar_inventario():
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT
                p.id,
                p.nombre,
                p.precio,
                p.stock,
                p.stock_minimo,
                p.categoria_id,
                c.nombre AS categoria_nombre
            FROM productos p
            LEFT JOIN categorias c ON c.id = p.categoria_id
            WHERE p.activo = TRUE
            ORDER BY p.stock ASC, p.nombre
            """
        )
        return cursor.fetchall()
    finally:
        conexion.close()


def aumentar_stock(producto_id: int, cantidad: int):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE productos SET stock = stock + %s WHERE id = %s AND activo = TRUE",
            (cantidad, producto_id),
        )
        conexion.commit()
        if cursor.rowcount == 0:
            return None
        cursor.execute("SELECT stock FROM productos WHERE id = %s", (producto_id,))
        return cursor.fetchone()[0]
    finally:
        conexion.close()


def listar_ids_productos_clip() -> list:
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute("SELECT id FROM productos WHERE activo = TRUE ORDER BY id ASC")
        return [fila[0] for fila in cursor.fetchall()]
    finally:
        conexion.close()


def obtener_producto_por_id(producto_id: int):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, nombre, precio FROM productos WHERE id = %s AND activo = TRUE",
            (producto_id,),
        )
        return cursor.fetchone()
    finally:
        conexion.close()


# ============================================================
# CARRITO / DETALLE DE VENTA
# ============================================================

def agregar_o_incrementar_producto(venta_id, producto_id, precio_unitario):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            INSERT INTO detalle_venta (venta_id, producto_id, cantidad, precio_unitario)
            VALUES (%s, %s, 1, %s)
            ON DUPLICATE KEY UPDATE cantidad = cantidad + 1
            """,
            (venta_id, producto_id, precio_unitario),
        )
        _recalcular_total(cursor, venta_id)
        conexion.commit()
    finally:
        conexion.close()


def incrementar_item(venta_id, producto_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE detalle_venta SET cantidad = cantidad + 1 WHERE venta_id = %s AND producto_id = %s",
            (venta_id, producto_id),
        )
        _recalcular_total(cursor, venta_id)
        conexion.commit()
    finally:
        conexion.close()


def decrementar_item(venta_id, producto_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            UPDATE detalle_venta
            SET cantidad = cantidad - 1
            WHERE venta_id = %s AND producto_id = %s AND cantidad > 1
            """,
            (venta_id, producto_id),
        )
        cursor.execute(
            """
            DELETE FROM detalle_venta
            WHERE venta_id = %s AND producto_id = %s AND cantidad <= 0
            """,
            (venta_id, producto_id),
        )
        _recalcular_total(cursor, venta_id)
        conexion.commit()
    finally:
        conexion.close()


def eliminar_item(venta_id, producto_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "DELETE FROM detalle_venta WHERE venta_id = %s AND producto_id = %s",
            (venta_id, producto_id),
        )
        _recalcular_total(cursor, venta_id)
        conexion.commit()
    finally:
        conexion.close()


# ============================================================
# DETECCIONES
# ============================================================

def registrar_deteccion(venta_id, producto_id, confianza):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "INSERT INTO detecciones (venta_id, producto_id, confianza, procesada) VALUES (%s, %s, %s, TRUE)",
            (venta_id, producto_id, confianza),
        )
        conexion.commit()
    finally:
        conexion.close()


# ============================================================
# CATEGORÍAS
# ============================================================

def listar_categorias():
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute("SELECT id, nombre, descripcion, color FROM categorias ORDER BY nombre")
        return cursor.fetchall()
    finally:
        conexion.close()


def crear_categoria(nombre, descripcion, color=None):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "INSERT INTO categorias (nombre, descripcion, color) VALUES (%s, %s, %s)",
            (nombre, descripcion, color),
        )
        conexion.commit()
        return cursor.lastrowid
    finally:
        conexion.close()


def actualizar_categoria(categoria_id, nombre, descripcion, color=None):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE categorias SET nombre = %s, descripcion = %s, color = %s WHERE id = %s",
            (nombre, descripcion, color, categoria_id),
        )
        conexion.commit()
        return cursor.rowcount > 0
    finally:
        conexion.close()


def eliminar_categoria(categoria_id):
    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute("DELETE FROM categorias WHERE id = %s", (categoria_id,))
        conexion.commit()
        return cursor.rowcount > 0
    finally:
        conexion.close()


def listar_ventas_cliente(usuario_id: int, limite: int = 20):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT
                v.id,
                v.estado,
                v.total,
                v.creado_en  AS fecha,
                v.metodo_pago,
                COALESCE(SUM(dv.cantidad), 0) AS cantidad_productos,
                GROUP_CONCAT(
                    CONCAT(dv.cantidad, 'x ', p.nombre)
                    ORDER BY dv.id SEPARATOR ', '
                ) AS resumen_productos
            FROM ventas v
            LEFT JOIN detalle_venta dv ON dv.venta_id = v.id
            LEFT JOIN productos p      ON p.id = dv.producto_id
            WHERE v.cliente_usuario_id = %s
            GROUP BY v.id, v.estado, v.total, v.creado_en, v.metodo_pago
            ORDER BY v.id DESC
            LIMIT %s
            """,
            (usuario_id, limite),
        )
        return cursor.fetchall()
    finally:
        conexion.close()


# ============================================================
# AUTENTICACIÓN
# ============================================================

def login_usuario(username: str, password: str):
    """
    Verifica las credenciales del usuario.
    Devuelve {"id", "username", "rol"} si son correctas, None si no.
    """
    import bcrypt as _bcrypt

    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, username, password, rol FROM usuarios WHERE username = %s",
            (username.strip(),),
        )
        usuario = cursor.fetchone()
        if usuario is None:
            return None
        ok = _bcrypt.checkpw(password.encode(), usuario["password"].encode())
        if not ok:
            return None
        return {
            "id":       usuario["id"],
            "username": usuario["username"],
            "rol":      usuario["rol"],
        }
    finally:
        conexion.close()


# ============================================================
# DASHBOARD
# ============================================================

def estadisticas_dashboard(dias: int = 30):
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)

        if dias > 0:
            fv = "WHERE v.estado = 'finalizada' AND v.creado_en >= DATE_SUB(NOW(), INTERVAL %s DAY)"
            fd = "JOIN ventas v ON v.id = dv.venta_id WHERE v.estado = 'finalizada' AND v.creado_en >= DATE_SUB(NOW(), INTERVAL %s DAY)"
            p = [dias]
        else:
            fv = "WHERE v.estado = 'finalizada'"
            fd = "JOIN ventas v ON v.id = dv.venta_id WHERE v.estado = 'finalizada'"
            p = []

        # ── Resumen ───────────────────────────────────────────
        cursor.execute(f"""
            SELECT COUNT(*) AS ventas,
                   COALESCE(SUM(v.total), 0)   AS ingresos,
                   COALESCE(AVG(v.total), 0)   AS ticket_promedio,
                   COALESCE(MAX(v.total), 0)   AS venta_mayor,
                   COUNT(v.cliente_usuario_id) AS con_factura
            FROM ventas v {fv}
        """, p)
        resumen = cursor.fetchone()

        cursor.execute(f"""
            SELECT COALESCE(SUM(dv.cantidad), 0) AS unidades
            FROM detalle_venta dv {fd}
        """, p)
        resumen['unidades'] = int(cursor.fetchone()['unidades'])
        resumen['ventas']         = int(resumen['ventas'])
        resumen['con_factura']    = int(resumen['con_factura'])
        resumen['ingresos']       = float(resumen['ingresos'])
        resumen['ticket_promedio']= float(resumen['ticket_promedio'])
        resumen['venta_mayor']    = float(resumen['venta_mayor'])

        # ── Por día ───────────────────────────────────────────
        cursor.execute(f"""
            SELECT DATE(v.creado_en) AS dia,
                   COUNT(*) AS ventas,
                   COALESCE(SUM(v.total), 0) AS ingresos
            FROM ventas v {fv}
            GROUP BY DATE(v.creado_en) ORDER BY dia
        """, p)
        por_dia = cursor.fetchall()
        for f in por_dia:
            f['dia'] = str(f['dia']); f['ventas'] = int(f['ventas']); f['ingresos'] = float(f['ingresos'])

        # ── Por método de pago ────────────────────────────────
        cursor.execute(f"""
            SELECT v.metodo_pago AS metodo, COUNT(*) AS ventas,
                   COALESCE(SUM(v.total), 0) AS ingresos
            FROM ventas v {fv}
            GROUP BY v.metodo_pago ORDER BY ingresos DESC
        """, p)
        por_metodo = cursor.fetchall()
        for f in por_metodo:
            f['ventas'] = int(f['ventas']); f['ingresos'] = float(f['ingresos'])

        # ── Por cajero ─────────────────────────────────────────
        por_cajero = [{"cajero": "Sin registrar", "ventas": resumen['ventas'], "ingresos": resumen['ingresos']}]

        # ── Top productos ─────────────────────────────────────
        cursor.execute(f"""
            SELECT p.nombre, SUM(dv.cantidad) AS unidades, SUM(dv.subtotal) AS ingresos
            FROM detalle_venta dv
            JOIN productos p ON p.id = dv.producto_id {fd}
            GROUP BY p.id, p.nombre ORDER BY unidades DESC LIMIT 10
        """, p)
        top_productos = cursor.fetchall()
        for f in top_productos:
            f['unidades'] = int(f['unidades']); f['ingresos'] = float(f['ingresos'])

        # ── Por categoría ─────────────────────────────────────
        cursor.execute(f"""
            SELECT c.nombre AS categoria, SUM(dv.cantidad) AS unidades, SUM(dv.subtotal) AS ingresos
            FROM detalle_venta dv
            JOIN productos p  ON p.id  = dv.producto_id
            JOIN categorias c ON c.id  = p.categoria_id {fd}
            GROUP BY c.id, c.nombre ORDER BY ingresos DESC
        """, p)
        por_categoria = cursor.fetchall()
        for f in por_categoria:
            f['unidades'] = int(f['unidades']); f['ingresos'] = float(f['ingresos'])

        # ── Top clientes ──────────────────────────────────────
        cursor.execute(f"""
            SELECT u.username AS cliente, NULL AS documento,
                   COUNT(*) AS compras, SUM(v.total) AS total
            FROM ventas v
            JOIN usuarios u ON u.id = v.cliente_usuario_id {fv}
              AND v.cliente_usuario_id IS NOT NULL
            GROUP BY v.cliente_usuario_id, u.username ORDER BY compras DESC LIMIT 5
        """, p)
        top_clientes = cursor.fetchall()
        for f in top_clientes:
            f['compras'] = int(f['compras']); f['total'] = float(f['total'])

        # ── Horas pico ────────────────────────────────────────
        cursor.execute(f"""
            SELECT HOUR(v.creado_en) AS hora, COUNT(*) AS ventas
            FROM ventas v {fv}
            GROUP BY HOUR(v.creado_en) ORDER BY ventas DESC LIMIT 5
        """, p)
        horas_pico = cursor.fetchall()
        for f in horas_pico:
            f['hora'] = int(f['hora']); f['ventas'] = int(f['ventas'])

        # ── Últimas ventas ────────────────────────────────────
        cursor.execute(f"""
            SELECT v.id, v.total, v.creado_en, v.metodo_pago,
                   'Sin registrar' AS cajero,
                   u.username AS cliente_nombre,
                   IF(v.cliente_usuario_id IS NOT NULL, 1, 0) AS factura
            FROM ventas v
            LEFT JOIN usuarios u ON u.id = v.cliente_usuario_id {fv}
            ORDER BY v.id DESC LIMIT 20
        """, p)
        ultimas = cursor.fetchall()
        for f in ultimas:
            f['id'] = int(f['id']); f['total'] = float(f['total'])
            f['factura'] = int(f['factura']); f['creado_en'] = str(f['creado_en'])

        return {
            "resumen": resumen, "por_dia": por_dia, "por_metodo": por_metodo,
            "por_cajero": por_cajero, "top_productos": top_productos,
            "por_categoria": por_categoria, "top_clientes": top_clientes,
            "horas_pico": horas_pico, "ultimas": ultimas,
        }
    finally:
        conexion.close()


# ============================================================
# USUARIOS
# ============================================================

ROLES_VALIDOS = ("administrador", "cajero", "cliente")
_USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,50}$")


class UsuarioDuplicado(Exception):
    """El nombre de usuario ya existe."""


def listar_usuarios():
    """Devuelve todos los usuarios SIN la contraseña."""
    conexion = _conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, username, rol, creado_en FROM usuarios "
            "ORDER BY FIELD(rol, 'administrador', 'cajero', 'cliente'), username"
        )
        filas = cursor.fetchall()
        for f in filas:
            f["creado_en"] = f["creado_en"].isoformat() if f["creado_en"] else None
        return filas
    finally:
        conexion.close()


def crear_usuario(username: str, password: str, rol: str) -> dict:
    """
    Crea un usuario con la contraseña hasheada (bcrypt, igual que el login).
    Lanza ValueError si los datos no son válidos y UsuarioDuplicado
    si el nombre de usuario ya existe.
    """
    import bcrypt as _bcrypt
    from mysql.connector import errors as _errores

    username = (username or "").strip()
    if not _USERNAME_RE.match(username):
        raise ValueError(
            "El usuario debe tener entre 3 y 50 caracteres: "
            "letras, números, punto, guion o guion bajo."
        )
    if rol not in ROLES_VALIDOS:
        raise ValueError("Rol no válido.")
    if len(password or "") < 6:
        raise ValueError("La contraseña debe tener al menos 6 caracteres.")
    if len(password.encode()) > 72:
        raise ValueError("La contraseña es demasiado larga (máximo 72 bytes).")

    hash_pw = _bcrypt.hashpw(password.encode(), _bcrypt.gensalt()).decode()

    conexion = _conexion()
    try:
        cursor = conexion.cursor()
        try:
            cursor.execute(
                "INSERT INTO usuarios (username, password, rol) VALUES (%s, %s, %s)",
                (username, hash_pw, rol),
            )
        except _errores.IntegrityError:
            raise UsuarioDuplicado(f'El usuario "{username}" ya existe.')
        conexion.commit()
        return {"id": cursor.lastrowid, "username": username, "rol": rol}
    finally:
        conexion.close()