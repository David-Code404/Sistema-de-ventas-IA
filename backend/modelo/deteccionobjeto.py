"""
API de la Caja Registradora IA (version web: usuarios y administrador).
Sin deteccion de productos por camara: no usa YOLO, CLIP ni FAISS.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import threading
import time
import uuid
from collections import Counter, deque
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Query, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from mysql.connector import Error as MySQLError
from pydantic import BaseModel, field_validator

import comprobante
import historial_pdf as historial_pdf_mod
import config
import db

# ══════════════════════════════════════════════════════════════
#  CONFIGURACION
# ══════════════════════════════════════════════════════════════
IMAGENES_DIR = Path(config.IMAGENES_DIR)
IMAGENES_DIR.mkdir(exist_ok=True)

# ══════════════════════════════════════════════════════════════
#  FASTAPI APP
# ══════════════════════════════════════════════════════════════
app = FastAPI(title="Caja Registradora IA - API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ══════════════════════════════════════════════════════════════
#  AUTENTICACION
# ══════════════════════════════════════════════════════════════
class LoginIn(BaseModel):
    username: str
    password: str

@app.post("/auth/login")
def login(datos: LoginIn):
    usuario = db.login_usuario(datos.username, datos.password)
    if usuario is None:
        raise HTTPException(status_code=401, detail="Usuario o contrasena incorrectos.")
    return usuario

@app.get("/salud")
def salud():
    return {"estado": "ok"}

# ══════════════════════════════════════════════════════════════
#  PRODUCTOS
# ══════════════════════════════════════════════════════════════
class ProductoNuevoIn(BaseModel):
    nombre: str
    precio: float
    categoria_id: int
    cantidad: int = 0
    stock_minimo: int = 5


@app.post("/productos", status_code=201)
def crear_producto(datos: ProductoNuevoIn):
    """Alta manual de un producto (sin videos ni reconocimiento por camara)."""
    if not datos.nombre.strip():
        raise HTTPException(status_code=422, detail="El nombre no puede estar vacio.")
    if datos.precio <= 0:
        raise HTTPException(status_code=422, detail="El precio debe ser mayor que cero.")
    if datos.cantidad < 0:
        raise HTTPException(status_code=422, detail="La cantidad no puede ser negativa.")
    if datos.stock_minimo < 0:
        raise HTTPException(status_code=422, detail="El stock minimo no puede ser negativo.")
    try:
        nuevo_id = db.crear_producto_clip(
            nombre=datos.nombre,
            precio=datos.precio,
            categoria_id=datos.categoria_id,
            stock=datos.cantidad,
            stock_minimo=datos.stock_minimo,
        )
    except MySQLError as e:
        raise HTTPException(status_code=500, detail=f"Error al crear el producto: {e}")
    return {"producto_id": nuevo_id}


@app.get("/productos")
def buscar_productos(
    nombre:       str | None   = None,
    precio_min:   float | None = None,
    precio_max:   float | None = None,
    categoria_id: int | None   = None,
):
    return db.buscar_productos(
        nombre=nombre,
        precio_min=precio_min,
        precio_max=precio_max,
        categoria_id=categoria_id,
    )

@app.get("/inventario")
def listar_inventario():
    return db.listar_inventario()

class AumentarStockIn(BaseModel):
    cantidad: int

@app.post("/inventario/{producto_id}/aumentar")
def aumentar_stock(producto_id: int, datos: AumentarStockIn):
    if datos.cantidad <= 0:
        raise HTTPException(status_code=422, detail="La cantidad debe ser mayor que cero.")
    nuevo_stock = db.aumentar_stock(producto_id, datos.cantidad)
    if nuevo_stock is None:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    return {"id": producto_id, "stock": nuevo_stock}

@app.post("/productos/{producto_id}/imagen", status_code=200)
async def subir_imagen_producto(producto_id: int, imagen: UploadFile = File(...)):
    ext       = Path(imagen.filename or "img.jpg").suffix.lower() or ".jpg"
    ruta      = IMAGENES_DIR / f"{producto_id}{ext}"
    contenido = await imagen.read()
    with open(ruta, "wb") as f:
        f.write(contenido)
    return {"ok": True, "path": str(ruta)}

@app.get("/productos/{producto_id}/imagen")
def obtener_imagen_producto(producto_id: int):
    for ext in [".jpg", ".jpeg", ".png", ".webp"]:
        ruta = IMAGENES_DIR / f"{producto_id}{ext}"
        if ruta.exists():
            return FileResponse(str(ruta))
    raise HTTPException(status_code=404, detail="Sin imagen")

class ActualizarProductoIn(BaseModel):
    nombre: str
    precio: float
    categoria_id: int
    stock_minimo: int = 5

@app.put("/productos/{producto_id}")
def actualizar_producto(producto_id: int, datos: ActualizarProductoIn):
    if not datos.nombre.strip():
        raise HTTPException(status_code=422, detail="El nombre no puede estar vacio.")
    if datos.precio <= 0:
        raise HTTPException(status_code=422, detail="El precio debe ser mayor que cero.")
    if datos.stock_minimo < 0:
        raise HTTPException(status_code=422, detail="El stock minimo no puede ser negativo.")
    try:
        ok = db.actualizar_producto(
            producto_id,
            datos.nombre,
            datos.precio,
            datos.categoria_id,
            stock_minimo=datos.stock_minimo,
        )
    except MySQLError as e:
        raise HTTPException(status_code=500, detail=f"Error al actualizar: {e}")
    if not ok:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    return {"id": producto_id, **datos.model_dump()}

@app.delete("/productos/{producto_id}", status_code=204)
def eliminar_producto(producto_id: int):
    try:
        ok = db.desactivar_producto(producto_id)
    except MySQLError as e:
        raise HTTPException(status_code=500, detail=f"Error al eliminar: {e}")
    if not ok:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    return Response(status_code=204)

class AsociarCategoriaIn(BaseModel):
    categoria_id: int

@app.put("/productos/{producto_id}/categoria")
def asociar_categoria(producto_id: int, datos: AsociarCategoriaIn):
    try:
        actualizado = db.asociar_categoria_producto(producto_id, datos.categoria_id)
    except MySQLError as e:
        if e.errno == 1452:
            raise HTTPException(status_code=400, detail="La categoria indicada no existe.")
        raise HTTPException(status_code=500, detail="Error al asociar la categoria.")
    if not actualizado:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")
    return {"id": producto_id, "categoria_id": datos.categoria_id}

# ══════════════════════════════════════════════════════════════
#  CATEGORIAS
# ══════════════════════════════════════════════════════════════
class CategoriaIn(BaseModel):
    nombre: str
    descripcion: str = ""
    color: str | None = None

    @field_validator("nombre")
    @classmethod
    def nombre_no_vacio(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("El nombre de la categoria no puede estar vacio.")
        if len(v) > 100:
            raise ValueError("El nombre no puede superar 100 caracteres.")
        return v

    @field_validator("descripcion")
    @classmethod
    def descripcion_valida(cls, v: str) -> str:
        v = (v or "").strip()
        if len(v) > 255:
            raise ValueError("La descripcion no puede superar 255 caracteres.")
        return v

    @field_validator("color")
    @classmethod
    def color_valido(cls, v: str | None) -> str | None:
        if not v:
            return None
        v = v.strip()
        if not re.fullmatch(r"#[0-9A-Fa-f]{6}", v):
            raise ValueError("El color debe ser un hex de 6 digitos, ej. #34D399")
        return v

@app.get("/categorias")
def listar_categorias():
    return db.listar_categorias()

@app.post("/categorias", status_code=201)
def crear_categoria(datos: CategoriaIn):
    try:
        nuevo_id = db.crear_categoria(datos.nombre, datos.descripcion, datos.color)
    except MySQLError as e:
        if e.errno == 1062:
            raise HTTPException(status_code=409, detail="Ya existe una categoria con ese nombre.")
        raise HTTPException(status_code=500, detail="Error al crear la categoria.")
    return {"id": nuevo_id, **datos.model_dump()}

@app.put("/categorias/{categoria_id}")
def editar_categoria(categoria_id: int, datos: CategoriaIn):
    try:
        ok = db.actualizar_categoria(categoria_id, datos.nombre, datos.descripcion, datos.color)
    except MySQLError as e:
        if e.errno == 1062:
            raise HTTPException(status_code=409, detail="Ya existe una categoria con ese nombre.")
        raise HTTPException(status_code=500, detail="Error al editar la categoria.")
    if not ok:
        raise HTTPException(status_code=404, detail="Categoria no encontrada.")
    return {"id": categoria_id, **datos.model_dump()}

@app.delete("/categorias/{categoria_id}", status_code=204)
def borrar_categoria(categoria_id: int):
    try:
        ok = db.eliminar_categoria(categoria_id)
    except MySQLError as e:
        if e.errno == 1451:
            raise HTTPException(status_code=409, detail="No se puede eliminar: hay productos asociados.")
        raise HTTPException(status_code=500, detail="Error al eliminar la categoria.")
    if not ok:
        raise HTTPException(status_code=404, detail="Categoria no encontrada.")
    return Response(status_code=204)

# ══════════════════════════════════════════════════════════════
#  VENTAS
# ══════════════════════════════════════════════════════════════
@app.post("/ventas/nueva")
def nueva_venta():
    venta_id = db.crear_venta()
    return {"venta_id": venta_id}

@app.get("/ventas/{venta_id}/carrito")
def carrito(venta_id: int):
    return db.obtener_carrito(venta_id)

@app.get("/ventas")
def listar_ventas(limite: int = 50):
    return db.listar_ventas(limite)

class ItemPedidoIn(BaseModel):
    producto_id: int
    cantidad: int

class PedidoIn(BaseModel):
    usuario_id: int
    items: list[ItemPedidoIn]

@app.post("/pedidos", status_code=201)
def crear_pedido(datos: PedidoIn):
    try:
        return db.crear_pedido(datos.usuario_id, [i.model_dump() for i in datos.items])
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

@app.get("/pedidos/pendientes")
def pedidos_pendientes():
    pedidos = db.listar_pedidos_pendientes()
    for p in pedidos:
        if hasattr(p["fecha"], "isoformat"):
            p["fecha"] = p["fecha"].isoformat()
        p["total"] = float(p["total"])
    return pedidos

class HistorialPdfIn(BaseModel):
    ids: list[int] = []

@app.post("/ventas/historial.pdf")
def historial_pdf(datos: HistorialPdfIn):
    ventas = db.obtener_historial_pdf(datos.ids or None)
    return Response(
        content=historial_pdf_mod.generar_pdf(ventas),
        media_type="application/pdf",
        headers={"Content-Disposition": 'attachment; filename="historial_ventas.pdf"'},
    )

@app.get("/ventas/cliente/{usuario_id}")
def ventas_cliente(usuario_id: int, limite: int = 20):
    return db.listar_ventas_cliente(usuario_id, limite)

@app.get("/dashboard/estadisticas")
def dashboard_estadisticas(dias: int = 30):
    return db.estadisticas_dashboard(dias)

class FinalizarVentaIn(BaseModel):
    metodo_pago: str
    monto_recibido: float | None = None
    pago_confirmado: bool = False
    factura: bool = False
    cliente_nombre: str | None = None
    cliente_documento: str | None = None
    cliente_tipo_documento: str | None = None
    cliente_email: str | None = None
    cliente_telefono: str | None = None
    cliente_direccion: str | None = None
    cliente_usuario_id: int | None = None
    cajero: str | None = None

@app.post("/ventas/{venta_id}/finalizar")
def finalizar_venta(venta_id: int, datos: FinalizarVentaIn):
    try:
        resultado = db.finalizar_venta(
            venta_id,
            datos.metodo_pago,
            monto_recibido=datos.monto_recibido,
            pago_confirmado=datos.pago_confirmado,
            factura=datos.factura,
            cliente_nombre=datos.cliente_nombre,
            cliente_documento=datos.cliente_documento,
            cliente_tipo_documento=datos.cliente_tipo_documento,
            cliente_email=datos.cliente_email,
            cliente_telefono=datos.cliente_telefono,
            cliente_direccion=datos.cliente_direccion,
            cliente_usuario_id=datos.cliente_usuario_id,
            cajero=datos.cajero,
        )
    except LookupError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    doc = (datos.cliente_documento or "").strip()
    nom = (datos.cliente_nombre    or "").strip()
    if doc and nom:
        try:
            db.guardar_o_actualizar_cliente(
                documento=doc,
                tipo_documento=(datos.cliente_tipo_documento or "").strip(),
                nombre=nom,
                email=(datos.cliente_email     or "").strip(),
                telefono=(datos.cliente_telefono  or "").strip(),
                direccion=(datos.cliente_direccion or "").strip(),
            )
        except Exception as ex:
            print(f"[guardar_cliente] no bloqueante: {ex}")

    return {"ok": True, "venta_id": venta_id, **resultado}

@app.post("/ventas/{venta_id}/items/{producto_id}/incrementar")
def incrementar_item(venta_id: int, producto_id: int):
    db.incrementar_item(venta_id, producto_id)
    return {"ok": True}

@app.post("/ventas/{venta_id}/items/{producto_id}/decrementar")
def decrementar_item(venta_id: int, producto_id: int):
    db.decrementar_item(venta_id, producto_id)
    return {"ok": True}

@app.delete("/ventas/{venta_id}/items/{producto_id}")
def eliminar_item(venta_id: int, producto_id: int):
    db.eliminar_item(venta_id, producto_id)
    return {"ok": True}

@app.get("/ventas/{venta_id}/detalle")
def detalle_venta(venta_id: int):
    return db.obtener_carrito(venta_id)

@app.get("/ventas/{venta_id}/comprobante.pdf")
def comprobante_pdf(
    venta_id:     int,
    atendido_por: str      = "",
    usuario_id:   int | None = Query(default=None),
    rol:          str      = Query(default=""),
):
    venta = db.obtener_comprobante(venta_id)
    if venta is None:
        raise HTTPException(status_code=404, detail="Venta no encontrada.")
    if venta["estado"] != "finalizada":
        raise HTTPException(status_code=400, detail="La venta aun no esta finalizada.")

    if rol == "cliente":
        if usuario_id is None or not db.verificar_propietario_venta(venta_id, usuario_id):
            raise HTTPException(
                status_code=403,
                detail="No tienes permiso para descargar este comprobante.",
            )

    cajero_nombre = venta.get("cajero") or atendido_por.strip()[:40] or None
    pdf    = comprobante.generar_pdf(venta, cajero_nombre)
    nombre = comprobante.numero(venta)
    return Response(
        content=pdf,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nombre}.pdf"'},
    )

@app.get("/clientes/{documento}")
def buscar_cliente(documento: str):
    cliente = db.buscar_cliente_por_documento(documento.strip())
    if cliente is None:
        raise HTTPException(status_code=404, detail="Cliente no encontrado.")
    for k, v in cliente.items():
        if hasattr(v, "isoformat"):
            cliente[k] = v.isoformat()
    return cliente

# ══════════════════════════════════════════════════════════════
#  USUARIOS
# ══════════════════════════════════════════════════════════════
class UsuarioNuevo(BaseModel):
    username: str
    password: str
    rol: str

@app.get("/usuarios")
def api_listar_usuarios():
    return db.listar_usuarios()

@app.post("/usuarios", status_code=201)
def api_crear_usuario(datos: UsuarioNuevo):
    try:
        return db.crear_usuario(datos.username, datos.password, datos.rol)
    except db.UsuarioDuplicado as e:
        raise HTTPException(status_code=409, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))