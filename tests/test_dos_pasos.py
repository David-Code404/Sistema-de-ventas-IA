"""Prueba de caja negra de las sesiones con token (JWT) y la verificacion en dos pasos.

Uso (con el backend encendido y la migracion 002 aplicada):
    python tests/test_dos_pasos.py [http://127.0.0.1:8000]

Crea 3 usuarios de prueba (administrador, cajero y cliente) y al final borra SOLO esos ids.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

import pyotp

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

    # ── 4. Verificacion en dos pasos ──────────────────────────
    print("\n== Verificacion en dos pasos ==")
    t = tokens["cajero"]
    c, d = llamar("GET", "/auth/2fa/estado", token=t)
    esperar("Estado inicial: desactivada", False, d.get("activo") if isinstance(d, dict) else None)
    esperar("Activar sin preparar -> 409", 409, llamar("POST", "/auth/2fa/activar", {"codigo": "123456"}, t)[0])
    c, d = llamar("POST", "/auth/2fa/preparar", token=t)
    esperar("Preparar -> 200", 200, c)
    secreto = d["secreto"]
    caso("La URI del QR es otpauth", d["uri"].startswith("otpauth://totp/"))
    esperar("Activar con codigo malo -> 422", 422, llamar("POST", "/auth/2fa/activar", {"codigo": "000000"}, t)[0])
    c, d = llamar("POST", "/auth/2fa/activar", {"codigo": pyotp.TOTP(secreto).now()}, t)
    esperar("Activar con codigo correcto -> 200", 200, c)
    respaldo = d["codigos_respaldo"]
    esperar("Entrega 8 codigos de respaldo", 8, len(respaldo))
    c, d = llamar("GET", "/auth/2fa/estado", token=t)
    esperar("Estado final: activada", True, d.get("activo"))

    c, d = login(roles["cajero"]["username"], clave)
    esperar("Login con 2FA activa -> 200", 200, c)
    caso("Login NO entrega token de sesion todavia", d.get("requiere_2fa") is True and "token" not in d)
    t2fa = d["token_2fa"]
    esperar("El token temporal no sirve como sesion -> 401", 401, llamar("GET", "/productos", token=t2fa)[0])
    esperar("Verificar con codigo malo -> 401", 401, llamar("POST", "/auth/2fa/verificar", {"token_2fa": t2fa, "codigo": "111111"})[0])
    # evita repetir el mismo codigo TOTP del paso anterior: se usa el siguiente intervalo
    codigo_ok = pyotp.TOTP(secreto).at(time.time() + 30)
    c, d = llamar("POST", "/auth/2fa/verificar", {"token_2fa": t2fa, "codigo": codigo_ok})
    esperar("Verificar con codigo correcto -> 200", 200, c)
    caso("Entrega token de sesion", bool(d.get("token")) and d.get("rol") == "cajero")
    esperar("La sesion nueva funciona", 200, llamar("GET", "/pedidos/pendientes", token=d.get("token"))[0])
    esperar("Verificar con token falso -> 401", 401, llamar("POST", "/auth/2fa/verificar", {"token_2fa": "x.y.z", "codigo": codigo_ok})[0])

    c, d = login(roles["cajero"]["username"], clave)
    c, d2 = llamar("POST", "/auth/2fa/verificar", {"token_2fa": d["token_2fa"], "codigo": respaldo[0]})
    esperar("Codigo de respaldo sirve -> 200", 200, c)
    sesion = d2.get("token")
    c, d = login(roles["cajero"]["username"], clave)
    esperar("El mismo codigo de respaldo no sirve dos veces -> 401", 401,
            llamar("POST", "/auth/2fa/verificar", {"token_2fa": d["token_2fa"], "codigo": respaldo[0]})[0])

    esperar("Desactivar con clave mala -> 401", 401, llamar("POST", "/auth/2fa/desactivar", {"password": "mala", "codigo": respaldo[1]}, sesion)[0])
    esperar("Desactivar con codigo malo -> 422", 422, llamar("POST", "/auth/2fa/desactivar", {"password": clave, "codigo": "222222"}, sesion)[0])
    esperar("Desactivar correctamente -> 200", 200, llamar("POST", "/auth/2fa/desactivar", {"password": clave, "codigo": respaldo[1]}, sesion)[0])
    c, d = login(roles["cajero"]["username"], clave)
    caso("Despues de desactivar el login vuelve a ser directo", c == 200 and bool(d.get("token")) and "requiere_2fa" not in d)

    # limite de intentos
    c, d = llamar("POST", "/auth/2fa/preparar", token=d["token"])
    esperar("Volver a preparar -> 200", 200, c)
    esperar("Activar de nuevo", 200, llamar("POST", "/auth/2fa/activar", {"codigo": pyotp.TOTP(d["secreto"]).now()}, tokens["cajero"])[0])
    c, d = login(roles["cajero"]["username"], clave)
    intentos = [llamar("POST", "/auth/2fa/verificar", {"token_2fa": d["token_2fa"], "codigo": "999999"})[0] for _ in range(6)]
    esperar("Tras 5 intentos fallidos se bloquea -> 429", 429, intentos[-1])
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
