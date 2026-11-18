"""
HU-26 - Tarea 1420: estructura de la promocion.

Define que datos tiene una promocion y que reglas debe cumplir, para que
las siguientes tareas de la HU-26 los reutilicen:
    1430 panel de creacion/edicion   -> PromocionIn + validar_promocion()
    1440 precio en el catalogo       -> calcular_precio_con_descuento()
    1450 precio en la venta/factura  -> calcular_precio_con_descuento()
    1460 desactivacion por fecha     -> columna `activa` + `fecha_fin`

Tabla: promociones (ver frontend/sql/migracion_hu26_1420_promociones.sql)
No importa YOLO ni nada de deteccion.
"""

import threading
import time
from datetime import date
from decimal import ROUND_HALF_UP, Decimal

from pydantic import BaseModel, Field

import db

# ── Reglas de la promocion ────────────────────────────────────
TIPOS_PROMOCION = ("producto", "categoria")
PORCENTAJE_MINIMO = Decimal("0.01")    # mayor que 0
PORCENTAJE_MAXIMO = Decimal("99.99")   # menor que 100 (nada gratis)
NOMBRE_MAXIMO = 100


class PromocionIn(BaseModel):
    """Datos que envia el frontend para crear o editar una promocion."""
    nombre:       str = Field(..., max_length=NOMBRE_MAXIMO)
    tipo:         str                   # 'producto' o 'categoria'
    producto_id:  int | None = None     # obligatorio si tipo = 'producto'
    categoria_id: int | None = None     # obligatorio si tipo = 'categoria'
    porcentaje:   Decimal               # ej. 15 = 15 % de descuento
    fecha_inicio: date                  # AAAA-MM-DD, incluida
    fecha_fin:    date                  # AAAA-MM-DD, incluida
    activa:       bool = True


def validar_promocion(datos: dict) -> dict:
    """
    Limpia y valida los datos de una promocion (sin consultar la base).
    Devuelve un dict normalizado listo para guardar.
    Lanza ValueError con un mensaje claro si algo no cumple las reglas.
    """
    nombre = " ".join(str(datos.get("nombre") or "").split())
    if len(nombre) < 3:
        raise ValueError("El nombre de la promocion debe tener al menos 3 caracteres.")
    if len(nombre) > NOMBRE_MAXIMO:
        raise ValueError(f"El nombre no puede superar {NOMBRE_MAXIMO} caracteres.")

    tipo = str(datos.get("tipo") or "").strip().lower()
    if tipo not in TIPOS_PROMOCION:
        raise ValueError("Tipo de promocion invalido. Usa: producto o categoria.")

    producto_id = datos.get("producto_id")
    categoria_id = datos.get("categoria_id")
    if tipo == "producto":
        if not producto_id:
            raise ValueError("Elige el producto al que se aplica la promocion.")
        categoria_id = None
    else:
        if not categoria_id:
            raise ValueError("Elige la categoria a la que se aplica la promocion.")
        producto_id = None

    try:
        porcentaje = Decimal(str(datos.get("porcentaje")))
        if not porcentaje.is_finite():
            raise ValueError
        porcentaje = porcentaje.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    except Exception:
        raise ValueError("El porcentaje de descuento debe ser un numero.")
    if porcentaje < PORCENTAJE_MINIMO or porcentaje > PORCENTAJE_MAXIMO:
        raise ValueError("El porcentaje de descuento debe ser mayor que 0 y menor que 100.")

    fecha_inicio = _a_fecha(datos.get("fecha_inicio"), "inicio")
    fecha_fin = _a_fecha(datos.get("fecha_fin"), "fin")
    if fecha_fin < fecha_inicio:
        raise ValueError("La fecha de fin no puede ser anterior a la fecha de inicio.")

    return {
        "nombre":       nombre,
        "tipo":         tipo,
        "producto_id":  int(producto_id) if producto_id else None,
        "categoria_id": int(categoria_id) if categoria_id else None,
        "porcentaje":   porcentaje,
        "fecha_inicio": fecha_inicio,
        "fecha_fin":    fecha_fin,
        "activa":       bool(datos.get("activa", True)),
    }


def verificar_en_base(promo: dict, excluir_id: int | None = None) -> None:
    """
    Reglas que necesitan la base de datos (para usar al crear o editar):
      * el producto existe y esta activo / la categoria existe;
      * no hay otra promocion ACTIVA para el mismo producto o categoria
        cuyas fechas se crucen con estas.
    `excluir_id` es el id de la promocion que se esta editando.
    Lanza LookupError si el destino no existe y ValueError si hay cruce.
    """
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)

        if promo["tipo"] == "producto":
            cursor.execute(
                "SELECT nombre FROM productos WHERE id = %s AND activo = TRUE",
                (promo["producto_id"],),
            )
            if cursor.fetchone() is None:
                raise LookupError("El producto no existe o esta desactivado.")
            campo, valor = "producto_id", promo["producto_id"]
        else:
            cursor.execute(
                "SELECT nombre FROM categorias WHERE id = %s",
                (promo["categoria_id"],),
            )
            if cursor.fetchone() is None:
                raise LookupError("La categoria no existe.")
            campo, valor = "categoria_id", promo["categoria_id"]

        if not promo.get("activa", True):
            return  # una promocion inactiva no choca con nadie

        # Dos rangos [a, b] y [c, d] se cruzan si a <= d y c <= b
        sql = (
            f"SELECT id, nombre, fecha_inicio, fecha_fin FROM promociones "
            f"WHERE {campo} = %s AND activa = TRUE "
            f"AND fecha_inicio <= %s AND fecha_fin >= %s"
        )
        params = [valor, promo["fecha_fin"], promo["fecha_inicio"]]
        if excluir_id is not None:
            sql += " AND id <> %s"
            params.append(excluir_id)
        cursor.execute(sql + " LIMIT 1", params)
        otra = cursor.fetchone()
        if otra:
            raise ValueError(
                f"Ya existe la promocion \"{otra['nombre']}\" activa del "
                f"{otra['fecha_inicio']:%d/%m/%Y} al {otra['fecha_fin']:%d/%m/%Y} "
                f"para el mismo {promo['tipo']}. Cambia las fechas o desactivala."
            )
    finally:
        conexion.close()


def esta_vigente(promo: dict, hoy: date | None = None) -> bool:
    """True si la promocion esta activa y hoy esta entre sus fechas (incluidas)."""
    hoy = hoy or date.today()
    inicio = _a_fecha(promo["fecha_inicio"], "inicio")
    fin = _a_fecha(promo["fecha_fin"], "fin")
    return bool(promo.get("activa", True)) and inicio <= hoy <= fin


def calcular_precio_con_descuento(precio, porcentaje) -> float:
    """Precio final redondeado a 2 decimales. Ej.: (4.00, 15) -> 3.40"""
    precio = Decimal(str(precio))
    porcentaje = Decimal(str(porcentaje))
    final = precio * (Decimal("100") - porcentaje) / Decimal("100")
    return float(final.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


# ══════════════════════════════════════════════════════════════
#  HU-26 - Tarea 1430: guardar y consultar promociones (panel admin)
# ══════════════════════════════════════════════════════════════

def es_administrador(usuario_id: int | None) -> bool:
    """True si el usuario existe y tiene rol administrador."""
    if not usuario_id:
        return False
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute("SELECT rol FROM usuarios WHERE id = %s", (usuario_id,))
        fila = cursor.fetchone()
        return fila is not None and fila["rol"] == "administrador"
    finally:
        conexion.close()


_SELECT_PROMOCION = """
    SELECT pr.id, pr.nombre, pr.tipo, pr.producto_id, pr.categoria_id,
           pr.porcentaje, pr.fecha_inicio, pr.fecha_fin, pr.activa,
           pr.desactivada_auto_en,  -- HU-26 1460
           pr.creado_en, pr.actualizado_en,
           p.nombre  AS producto_nombre,
           p.precio  AS producto_precio,
           c.nombre  AS categoria_nombre
    FROM promociones pr
    LEFT JOIN productos  p ON p.id = pr.producto_id
    LEFT JOIN categorias c ON c.id = pr.categoria_id
"""


def _estado(promo: dict, hoy: date) -> str:
    """
    'vencida' (ya paso su fecha fin, este activa o no), 'inactiva'
    (desactivada a mano), 'programada' (aun no empieza) o 'vigente'.
    """
    if hoy > promo["fecha_fin"]:
        return "vencida"
    if not promo["activa"]:
        return "inactiva"
    if hoy < promo["fecha_inicio"]:
        return "programada"
    return "vigente"


def _serializar(promo: dict, hoy: date) -> dict:
    promo["activa"] = bool(promo["activa"])
    promo["estado"] = _estado(promo, hoy)
    promo["porcentaje"] = float(promo["porcentaje"])
    if promo.get("producto_precio") is not None:
        promo["producto_precio"] = float(promo["producto_precio"])
        promo["precio_con_descuento"] = calcular_precio_con_descuento(
            promo["producto_precio"], promo["porcentaje"])
    for k in ("fecha_inicio", "fecha_fin", "creado_en", "actualizado_en",
              "desactivada_auto_en"):
        if hasattr(promo.get(k), "isoformat"):
            promo[k] = promo[k].isoformat()
    return promo


def listar_promociones() -> list[dict]:
    """Todas las promociones: primero las activas, luego por fecha de inicio."""
    desactivar_vencidas()  # HU-26 1460: el panel siempre muestra el estado al dia
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            _SELECT_PROMOCION
            + " ORDER BY pr.activa DESC, pr.fecha_inicio DESC, pr.id DESC"
        )
        hoy = date.today()
        return [_serializar(f, hoy) for f in cursor.fetchall()]
    finally:
        conexion.close()


def obtener_promocion(promocion_id: int) -> dict | None:
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(_SELECT_PROMOCION + " WHERE pr.id = %s", (promocion_id,))
        fila = cursor.fetchone()
        return None if fila is None else _serializar(fila, date.today())
    finally:
        conexion.close()


def _validar_para_guardar(datos: dict, excluir_id: int | None = None) -> dict:
    promo = validar_promocion(datos)
    if promo["fecha_fin"] < date.today():
        raise ValueError("La fecha de fin ya paso. Elige una fecha de hoy en adelante.")
    verificar_en_base(promo, excluir_id=excluir_id)
    return promo


def crear_promocion(datos: dict) -> dict:
    """Valida y guarda una promocion nueva. Devuelve la promocion guardada."""
    promo = _validar_para_guardar(datos)
    conexion = db._conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            INSERT INTO promociones
                (nombre, tipo, producto_id, categoria_id, porcentaje,
                 fecha_inicio, fecha_fin, activa)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (promo["nombre"], promo["tipo"], promo["producto_id"], promo["categoria_id"],
             promo["porcentaje"], promo["fecha_inicio"], promo["fecha_fin"],
             1 if promo["activa"] else 0),
        )
        conexion.commit()
        nuevo_id = cursor.lastrowid
    finally:
        conexion.close()
    return obtener_promocion(nuevo_id)


def actualizar_promocion(promocion_id: int, datos: dict) -> dict:
    """Edita una promocion existente. Lanza LookupError si no existe."""
    if obtener_promocion(promocion_id) is None:
        raise LookupError("Promocion no encontrada.")
    promo = _validar_para_guardar(datos, excluir_id=promocion_id)
    conexion = db._conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            """
            UPDATE promociones
            SET nombre = %s, tipo = %s, producto_id = %s, categoria_id = %s,
                porcentaje = %s, fecha_inicio = %s, fecha_fin = %s, activa = %s,
                desactivada_auto_en = NULL  -- HU-26 1460: al editar se olvida el aviso
            WHERE id = %s
            """,
            (promo["nombre"], promo["tipo"], promo["producto_id"], promo["categoria_id"],
             promo["porcentaje"], promo["fecha_inicio"], promo["fecha_fin"],
             1 if promo["activa"] else 0, promocion_id),
        )
        conexion.commit()
    finally:
        conexion.close()
    return obtener_promocion(promocion_id)


def cambiar_estado_promocion(promocion_id: int, activa: bool) -> dict:
    """
    Activa o desactiva una promocion sin tocar sus demas datos.
    Al activarla se revisa que no se cruce con otra activa del mismo destino.
    """
    actual = obtener_promocion(promocion_id)
    if actual is None:
        raise LookupError("Promocion no encontrada.")
    if activa:
        if date.fromisoformat(actual["fecha_fin"]) < date.today():
            raise ValueError("No se puede activar: la promocion ya vencio. Edita sus fechas.")
        verificar_en_base(
            {**actual,
             "fecha_inicio": date.fromisoformat(actual["fecha_inicio"]),
             "fecha_fin": date.fromisoformat(actual["fecha_fin"]),
             "activa": True},
            excluir_id=promocion_id,
        )
    conexion = db._conexion()
    try:
        cursor = conexion.cursor()
        cursor.execute(
            "UPDATE promociones SET activa = %s, desactivada_auto_en = NULL WHERE id = %s",
            (1 if activa else 0, promocion_id),
        )
        conexion.commit()
    finally:
        conexion.close()
    return obtener_promocion(promocion_id)


# ══════════════════════════════════════════════════════════════
#  HU-26 - Tarea 1440: ofertas vigentes para el catalogo del cliente
# ══════════════════════════════════════════════════════════════

_SQL_OFERTAS = """
    SELECT p.id AS producto_id, p.precio,
           pr.id AS promocion_id, pr.nombre AS promocion_nombre,
           pr.tipo, pr.porcentaje, pr.fecha_fin
    FROM productos p
    JOIN promociones pr
      ON (pr.tipo = 'producto'  AND pr.producto_id  = p.id)
      OR (pr.tipo = 'categoria' AND pr.categoria_id = p.categoria_id)
    WHERE p.activo = TRUE
      AND pr.activa = TRUE
      AND pr.fecha_inicio <= %s AND pr.fecha_fin >= %s
      {filtro}
    ORDER BY p.id,
             pr.porcentaje DESC,
             (pr.tipo = 'producto') DESC,
             pr.id DESC
"""


def _mejores_ofertas(filas) -> dict[int, dict]:
    """Se queda con la mejor oferta de cada producto (la primera por el ORDER BY)."""
    mejores: dict[int, dict] = {}
    for f in filas:
        if f["producto_id"] in mejores:
            continue
        precio = float(f["precio"])
        porcentaje = float(f["porcentaje"])
        mejores[f["producto_id"]] = {
            "producto_id":      f["producto_id"],
            "precio_original":  round(precio, 2),
            "precio_oferta":    calcular_precio_con_descuento(precio, porcentaje),
            "porcentaje":       porcentaje,
            "promocion_id":     f["promocion_id"],
            "promocion_nombre": f["promocion_nombre"],
            "tipo":             f["tipo"],
            "fecha_fin":        f["fecha_fin"].isoformat(),
        }
    return mejores


def ofertas_vigentes(hoy: date | None = None) -> list[dict]:
    """
    Una fila por cada producto ACTIVO que hoy tiene descuento, con su precio
    original y su precio de oferta. Si al producto le corresponden dos
    promociones (una propia y otra de su categoria), gana la de MAYOR descuento;
    si empatan, la propia del producto.
    """
    hoy = hoy or date.today()
    conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(_SQL_OFERTAS.format(filtro=""), (hoy, hoy))
        return list(_mejores_ofertas(cursor.fetchall()).values())
    finally:
        conexion.close()


# ══════════════════════════════════════════════════════════════
#  HU-26 - Tarea 1450: precio a cobrar en la venta y en el pedido
# ══════════════════════════════════════════════════════════════

def oferta_de_producto(producto_id: int, conexion=None, hoy: date | None = None) -> dict | None:
    """
    Mejor oferta vigente HOY para un producto, o None si no tiene.
    Si se pasa `conexion`, se usa esa (sirve dentro de una transaccion) y no
    se cierra; si no, abre y cierra una propia.
    """
    hoy = hoy or date.today()
    propia = conexion is None
    if propia:
        conexion = db._conexion()
    try:
        cursor = conexion.cursor(dictionary=True)
        cursor.execute(
            _SQL_OFERTAS.format(filtro="AND p.id = %s"), (hoy, hoy, producto_id))
        filas = cursor.fetchall()
        cursor.close()
        return _mejores_ofertas(filas).get(producto_id)
    finally:
        if propia:
            conexion.close()


def precio_a_cobrar(producto_id: int, precio_normal, conexion=None) -> dict:
    """
    Precio que se debe cobrar hoy por un producto:
        {"precio": 1.60, "precio_original": 2.00, "promocion_id": 7}
    Sin promocion: {"precio": precio_normal, "precio_original": None, "promocion_id": None}
    """
    oferta = oferta_de_producto(producto_id, conexion)
    if oferta is None:
        return {"precio": round(float(precio_normal), 2),
                "precio_original": None, "promocion_id": None}
    return {"precio": oferta["precio_oferta"],
            "precio_original": oferta["precio_original"],
            "promocion_id": oferta["promocion_id"]}


# ══════════════════════════════════════════════════════════════
#  HU-26 - Tarea 1460: desactivacion automatica al vencer la fecha fin
# ══════════════════════════════════════════════════════════════

# Cada cuanto revisa el backend si hay promociones vencidas (segundos)
INTERVALO_REVISION_SEGUNDOS = 10 * 60

_hilo_revision: threading.Thread | None = None
_parar_revision = threading.Event()


def desactivar_vencidas(hoy: date | None = None) -> list[dict]:
    """
    Desactiva las promociones ACTIVAS cuya fecha_fin ya paso (fecha_fin < hoy)
    y anota cuando se hizo en `desactivada_auto_en`.
    Devuelve las promociones que se desactivaron en esta llamada
    ([] si no habia ninguna). Se puede llamar las veces que sea: es idempotente.
    """
    hoy = hoy or date.today()
    conexion = db._conexion()
    try:
        conexion.autocommit = False
        cursor = conexion.cursor(dictionary=True)
        # Se bloquean las filas para que dos revisiones a la vez no se pisen
        cursor.execute(
            "SELECT id, nombre, fecha_fin FROM promociones "
            "WHERE activa = TRUE AND fecha_fin < %s FOR UPDATE",
            (hoy,),
        )
        vencidas = cursor.fetchall()
        if vencidas:
            marcadores = ", ".join(["%s"] * len(vencidas))
            cursor.execute(
                f"UPDATE promociones SET activa = FALSE, desactivada_auto_en = NOW() "
                f"WHERE id IN ({marcadores})",
                [v["id"] for v in vencidas],
            )
        conexion.commit()
        return [{"id": v["id"], "nombre": v["nombre"],
                 "fecha_fin": v["fecha_fin"].isoformat()} for v in vencidas]
    except Exception:
        conexion.rollback()
        raise
    finally:
        conexion.close()


def _ciclo_revision(intervalo: int):
    while not _parar_revision.is_set():
        try:
            desactivadas = desactivar_vencidas()
            for p in desactivadas:
                print(f"[promociones] Desactivada automaticamente: "
                      f"#{p['id']} {p['nombre']} (vencio el {p['fecha_fin']})", flush=True)
        except Exception as e:  # sin base de datos, se reintenta en el proximo ciclo
            print(f"[promociones] No se pudo revisar vencidas: {e}", flush=True)
        _parar_revision.wait(intervalo)


def iniciar_revision_automatica(intervalo: int = INTERVALO_REVISION_SEGUNDOS):
    """
    Arranca (una sola vez) un hilo en segundo plano que revisa las promociones
    vencidas al iniciar el backend y luego cada `intervalo` segundos.
    """
    global _hilo_revision
    if _hilo_revision is not None and _hilo_revision.is_alive():
        return
    _parar_revision.clear()
    _hilo_revision = threading.Thread(
        target=_ciclo_revision, args=(intervalo,),
        name="revision-promociones-vencidas", daemon=True,
    )
    _hilo_revision.start()


def detener_revision_automatica():
    _parar_revision.set()


def _a_fecha(valor, cual: str) -> date:
    if isinstance(valor, date):
        return valor
    try:
        return date.fromisoformat(str(valor))
    except Exception:
        raise ValueError(f"La fecha de {cual} no es valida (usa AAAA-MM-DD).")