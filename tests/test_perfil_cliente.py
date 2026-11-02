"""Prueba de caja negra del perfil del cliente (nombre, correo, direccion y contraseña).

Uso (con el backend encendido):  python tests/test_perfil_cliente.py [http://127.0.0.1:8000]
Crea 2 clientes de prueba y al final borra SOLO esos registros (por id).
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
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read())
        except ValueError:
            return e.code, {}


def esperar(nombre, esperado, obtenido):
    ok = esperado == obtenido
    resultados.append(ok)
    print(("PASA  " if ok else "FALLA ") + nombre + f"   [esperado {esperado}, obtenido {obtenido}]")


sufijo = uuid.uuid4().hex[:6]
clave = "Prueba-" + sufijo
ids_usuario, documentos = [], []
try:
    registrados = []
    for i in (1, 2):
        # documento unico por corrida (7 digitos) para no chocar con datos reales
        doc = str(int(uuid.uuid4().int % 9000000) + 1000000)
        r = db.registrar_cliente(f"zz_{sufijo}_{i}@prueba.com", clave, f"Cliente Prueba {i}", "CI", doc,
                                 "70000000", "Calle 1")
        ids_usuario.append(r["id"])
        documentos.append(doc)
        registrados.append(r)
    a, b = registrados
    c, d = llamar("POST", "/auth/login", {"username": a["username"], "password": clave})
    esperar("Login del cliente", 200, c)
    tok = d["token"]

    c, d = llamar("GET", "/mi-perfil", token=tok)
    esperar("Ver mi perfil", 200, c)
    esperar("El perfil es el mio", a["username"], d.get("email"))

    nuevo = f"zz_{sufijo}_nuevo@prueba.com"
    c, d = llamar("PUT", "/mi-perfil", {"nombre": "Nombre Nuevo", "email": nuevo, "direccion": "Av. Nueva 123"}, tok)
    esperar("Editar nombre, correo y direccion", 200, c)
    esperar("Devuelve el correo nuevo como usuario", nuevo, d.get("username"))
    c, d = llamar("GET", "/mi-perfil", token=tok)
    esperar("Los cambios quedan guardados (nombre)", "Nombre Nuevo", d.get("nombre"))
    esperar("Los cambios quedan guardados (direccion)", "Av. Nueva 123", d.get("direccion"))
    c, _ = llamar("POST", "/auth/login", {"username": a["username"], "password": clave})
    esperar("El correo viejo ya no inicia sesion", 401, c)
    c, _ = llamar("POST", "/auth/login", {"username": nuevo, "password": clave})
    esperar("El correo nuevo inicia sesion", 200, c)

    c, _ = llamar("PUT", "/mi-perfil", {"nombre": "Nombre Valido", "email": b["username"], "direccion": "Calle"}, tok)
    esperar("Correo de otra cuenta -> 409", 409, c)
    c, _ = llamar("PUT", "/mi-perfil", {"nombre": "", "email": nuevo, "direccion": "Calle"}, tok)
    esperar("Nombre vacio -> 422", 422, c)
    c, _ = llamar("PUT", "/mi-perfil", {"nombre": "Nombre Valido", "email": "no-es-correo", "direccion": "Calle"}, tok)
    esperar("Correo invalido -> 422", 422, c)
    c, _ = llamar("PUT", "/mi-perfil", {"nombre": "Nombre Valido", "email": nuevo, "direccion": "  "}, tok)
    esperar("Direccion vacia -> 422", 422, c)
    c, _ = llamar("PUT", "/mi-perfil", {"nombre": "Nombre Valido", "email": nuevo, "direccion": "a" * 151}, tok)
    esperar("Direccion de mas de 150 caracteres -> 422", 422, c)

    c, _ = llamar("GET", "/mi-perfil")
    esperar("Sin sesion -> 401", 401, c)
    c, d = llamar("POST", "/auth/login", {"username": "admin", "password": "x"})
    c, _ = llamar("PUT", f"/clientes/{documentos[1]}", {"nombre": "Hack", "email": "h@h.com", "direccion": "x"}, tok)
    esperar("El cliente no puede editar fichas por documento -> 403", 403, c)

    c, _ = llamar("POST", "/auth/cambiar-password",
                  {"usuario_id": a["id"], "password_actual": clave, "password_nueva": "Otra-" + sufijo}, tok)
    esperar("Cambiar mi contraseña -> 200", 200, c)
    c, _ = llamar("POST", "/auth/login", {"username": nuevo, "password": "Otra-" + sufijo})
    esperar("Entra con la contraseña nueva", 200, c)
finally:
    conexion = db._conexion()
    try:
        cur = conexion.cursor()
        for doc in documentos:
            cur.execute("DELETE FROM clientes WHERE documento = %s", (doc,))
        for i in ids_usuario:
            cur.execute("DELETE FROM usuarios WHERE id = %s", (i,))
        conexion.commit()
    finally:
        conexion.close()
    print(f"\nBorrados: usuarios {ids_usuario}, clientes {documentos}")

print(f"\nResultado: {sum(resultados)} de {len(resultados)} casos pasaron.")
sys.exit(0 if all(resultados) else 1)
