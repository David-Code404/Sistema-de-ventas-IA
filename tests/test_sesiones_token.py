"""Prueba de caja negra de las sesiones con token (JWT) y los permisos por rol.

Uso (con el backend encendido):
    python tests/test_sesiones_token.py [http://127.0.0.1:8000]

Crea 3 usuarios de prueba (administrador, cajero y cliente) y al final borra SOLO esos ids.
"""
import json
import os
import sys
import urllib.error
import urllib.request
import uuid


RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "backend", "modelo"))
import db  # noqa: E402

API = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
resultados = []


def llamar(metodo, ruta, cuerpo=None, token=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    cab = {"Content-Type": "application/json"}
    if token:
        cab["Authorization"] = "Bearer " + token
    req = urllib.request.Request(API + ruta, data=datos, headers=cab, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            cuerpo_r = r.read()
            codigo = r.status
    except urllib.error.HTTPError as e:
        cuerpo_r = e.read()
        codigo = e.code
    try:
        return codigo, json.loads(cuerpo_r)
    except ValueError:
        return codigo, cuerpo_r


def caso(nombre, ok, detalle=""):
    resultados.append((nombre, ok, detalle))
    print(("PASA  " if ok else "FALLA ") + nombre + (f"   [{detalle}]" if detalle else ""))


def esperar(nombre, esperado, obtenido):
    caso(nombre, obtenido == esperado, f"esperado {esperado}, obtenido {obtenido}")


def login(usuario, clave):
    return llamar("POST", "/auth/login", {"username": usuario, "password": clave})


sufijo = uuid.uuid4().hex[:6]
clave = "Prueba-" + sufijo
ids = []
try:
    roles = {}
    for rol in ("administrador", "cajero", "cliente"):
        nombre = f"zz_{rol[:4]}_{sufijo}"
        u = db.crear_usuario(nombre, clave, rol)
        ids.append(u["id"])
        roles[rol] = {"id": u["id"], "username": nombre}

    # ── 1. Sin sesion ─────────────────────────────────────────
    print("\n== Sin sesion ==")
    esperar("GET /salud es publico", 200, llamar("GET", "/salud")[0])
    esperar("GET /productos sin token -> 401", 401, llamar("GET", "/productos")[0])
    esperar("GET /productos con token falso -> 401", 401, llamar("GET", "/productos", token="abc.def.ghi")[0])
    esperar("Login con clave mala -> 401", 401, login(roles["cajero"]["username"], "mala")[0])

    tokens = {}
    for rol, d in roles.items():
        c, cuerpo = login(d["username"], clave)
        esperar(f"Login {rol} -> 200", 200, c)
        tokens[rol] = cuerpo.get("token") if isinstance(cuerpo, dict) else None
        caso(f"Login {rol} entrega token", bool(tokens[rol]))

    # ── 2. Permisos por rol ──────────────────────────────────
    print("\n== Permisos por rol ==")
    esperar("Administrador: GET /usuarios -> 200", 200, llamar("GET", "/usuarios", token=tokens["administrador"])[0])
    esperar("Cajero: GET /usuarios -> 403", 403, llamar("GET", "/usuarios", token=tokens["cajero"])[0])
    esperar("Cliente: GET /usuarios -> 403", 403, llamar("GET", "/usuarios", token=tokens["cliente"])[0])
    esperar("Cliente: GET /dashboard/estadisticas -> 403", 403, llamar("GET", "/dashboard/estadisticas", token=tokens["cliente"])[0])
    esperar("Cliente: GET /pedidos/pendientes -> 403", 403, llamar("GET", "/pedidos/pendientes", token=tokens["cliente"])[0])
    esperar("Cajero: GET /pedidos/pendientes -> 200", 200, llamar("GET", "/pedidos/pendientes", token=tokens["cajero"])[0])
    esperar("Cliente: GET /productos -> 200", 200, llamar("GET", "/productos", token=tokens["cliente"])[0])
    esperar("Cliente: POST /productos -> 403", 403, llamar("POST", "/productos", {}, tokens["cliente"])[0])
    esperar("Cajero: POST /productos -> 403", 403, llamar("POST", "/productos", {}, tokens["cajero"])[0])
    esperar("Cajero: POST /pedidos -> 403", 403, llamar("POST", "/pedidos", {"usuario_id": roles["cajero"]["id"], "items": []}, tokens["cajero"])[0])
    esperar("Cliente: ventas de otra persona -> 403", 403, llamar("GET", f"/ventas/cliente/{roles['cajero']['id']}", token=tokens["cliente"])[0])
    esperar("Cliente: sus propias ventas -> 200", 200, llamar("GET", f"/ventas/cliente/{roles['cliente']['id']}", token=tokens["cliente"])[0])
    esperar("Cliente: ficha de otro documento -> 403", 403, llamar("GET", "/clientes/00000000", token=tokens["cliente"])[0])

    # ── 3. Identidad ──────────────────────────────────────────
    print("\n== Identidad ==")
    otro = roles["administrador"]["id"]
    esperar("Cambiar clave de otra persona -> 403", 403,
            llamar("POST", "/auth/cambiar-password", {"usuario_id": otro, "password_actual": clave, "password_nueva": "Nueva-123"}, tokens["cliente"])[0])
    c, _ = llamar("POST", "/pedidos", {"usuario_id": otro, "items": [{"producto_id": 1, "cantidad": 1}]}, tokens["cliente"])
    esperar("Pedido a nombre de otra persona -> 403", 403, c)

    conexion = db._conexion()
    try:
        cur = conexion.cursor()
        cur.execute("SELECT id FROM ventas ORDER BY id LIMIT 1")
        fila = cur.fetchone()
    finally:
        conexion.close()
    if fila:
        c, _ = llamar("GET", f"/ventas/{fila[0]}/comprobante?rol=administrador&usuario_id={otro}", token=tokens["cliente"])
        caso("Cliente no puede hacerse pasar por administrador en el comprobante", c in (400, 403, 404), f"codigo {c}")
    else:
        caso("Comprobante suplantado (sin ventas en la base)", True, "omitida")
finally:
    # Limpieza: solo los ids creados arriba
    conexion = db._conexion()
    try:
        cur = conexion.cursor()
        for i in ids:
            cur.execute("DELETE FROM usuarios WHERE id = %s", (i,))
        conexion.commit()
    finally:
        conexion.close()
    print(f"\nUsuarios de prueba borrados: {ids}")

fallos = [r for r in resultados if not r[1]]
print(f"\nResultado: {len(resultados) - len(fallos)} de {len(resultados)} casos pasaron.")
for n, _, d in fallos:
    print("  FALLO:", n, "-", d)
sys.exit(1 if fallos else 0)
