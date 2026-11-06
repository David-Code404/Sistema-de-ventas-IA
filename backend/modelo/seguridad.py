"""
Sesiones con token (JWT) y permisos por rol.

- Al iniciar sesion la API entrega un token firmado que el frontend manda en
  cada peticion (Authorization: Bearer ...).
- AutenticacionMiddleware revisa ese token en TODAS las rutas, salvo las
  publicas, y aplica los permisos segun el rol (administrador, cajero, cliente).

No importa YOLO ni nada de deteccion.
"""

import re
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qsl, unquote, urlencode

import jwt
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

import config

ALGORITMO = "HS256"
HORAS_SESION = 8

# Clave de firma. Se define en la variable de entorno JWT_SECRET; si falta, se usa
# una aleatoria (las sesiones se cierran cada vez que el servidor se reinicia).
JWT_SECRET = getattr(config, "JWT_SECRET", "") or ""
if not JWT_SECRET:
    import secrets

    JWT_SECRET = secrets.token_urlsafe(48)
    print("AVISO: no hay JWT_SECRET; se usa una clave temporal (las sesiones se pierden al reiniciar).")


# ══════════════════════════════════════════════════════════════
#  TOKENS
# ══════════════════════════════════════════════════════════════
def _ahora():
    return datetime.now(timezone.utc)


def crear_token(usuario: dict) -> str:
    """Token de sesion de 8 horas. usuario: {"id", "username", "rol", "cliente"?}."""
    datos = {
        "typ": "acceso",
        "sub": str(usuario["id"]),
        "u": usuario["username"],
        "rol": usuario["rol"],
        "iat": _ahora(),
        "exp": _ahora() + timedelta(hours=HORAS_SESION),
    }
    ficha = usuario.get("cliente") or {}
    if ficha.get("documento"):
        datos["doc"] = str(ficha["documento"]).upper()
    return jwt.encode(datos, JWT_SECRET, algorithm=ALGORITMO)


def leer_token(token: str, tipo: str = "acceso"):
    """Devuelve el contenido del token si es valido y del tipo pedido; si no, None."""
    try:
        datos = jwt.decode(token, JWT_SECRET, algorithms=[ALGORITMO])
    except jwt.PyJWTError:
        return None
    if datos.get("typ") != tipo:
        return None
    return datos


# ══════════════════════════════════════════════════════════════
#  PERMISOS POR RUTA
# ══════════════════════════════════════════════════════════════
PERSONAL = {"administrador", "cajero"}
TODOS = {"administrador", "cajero", "cliente"}

# (metodos, expresion de la ruta)
PUBLICAS = [
    ("POST", r"^/auth/login$"),
    ("POST", r"^/auth/registro$"),
    ("GET", r"^/salud$"),
    ("GET", r"^/(docs|redoc|openapi\.json|docs/oauth2-redirect)$"),
    ("GET", r"^/productos/\d+/imagen$"),   # las imagenes se cargan sin cabeceras
]
CUALQUIER_ROL = [
    ("GET", r"^/(productos|categorias|inventario|inventario/stock-bajo)$"),
    ("POST", r"^/auth/cambiar-password$"),
    ("GET", r"^/ventas/\d+/comprobante(\.pdf)?$"),
]
SOLO_CLIENTE = [("POST", r"^/pedidos$"), ("GET|PUT", r"^/mi-perfil$")]
SOLO_ADMIN = [
    ("GET|POST|PUT|DELETE", r"^/usuarios"),
    ("GET", r"^/dashboard/estadisticas$"),
    ("POST|PUT|DELETE", r"^/(productos|categorias)"),
    ("POST|PUT", r"^/inventario/"),
    ("POST|GET", r"^/registro/producto"),
]


def _coincide(reglas, metodo, ruta):
    return any(metodo in m.split("|") and re.search(p, ruta) for m, p in reglas)


def _negar(codigo: int, detalle: str):
    return JSONResponse({"detail": detalle}, status_code=codigo)


class AutenticacionMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        metodo, ruta = request.method, request.url.path
        if metodo == "OPTIONS" or _coincide(PUBLICAS, metodo, ruta):
            return await call_next(request)

        cabecera = request.headers.get("authorization", "")
        token = cabecera[7:].strip() if cabecera.lower().startswith("bearer ") else ""
        datos = leer_token(token) if token else None
        if datos is None:
            return _negar(401, "Sesion no valida o vencida. Vuelve a iniciar sesion.")
        usuario = {"id": int(datos["sub"]), "username": datos.get("u", ""), "rol": datos["rol"],
                   "doc": datos.get("doc")}
        rol = usuario["rol"]

        if _coincide(SOLO_ADMIN, metodo, ruta):
            permitido = rol == "administrador"
        elif _coincide(SOLO_CLIENTE, metodo, ruta):
            permitido = rol == "cliente"
        elif _coincide(CUALQUIER_ROL, metodo, ruta):
            permitido = rol in TODOS
        elif rol == "cliente":
            # Un cliente solo ve sus propias compras y su propia ficha
            propia = re.match(r"^/ventas/cliente/(\d+)$", ruta)
            ficha = re.match(r"^/clientes/([^/]+)$", ruta)
            permitido = bool(
                (propia and metodo == "GET" and int(propia.group(1)) == usuario["id"])
                or (ficha and metodo == "GET" and usuario["doc"]
                    and unquote(ficha.group(1)).strip().upper() == usuario["doc"])
            )
        else:
            permitido = rol in PERSONAL
        if not permitido:
            return _negar(403, "No tienes permiso para esta accion.")

        # Un cliente no puede hacerse pasar por personal ni por otro cliente al pedir comprobantes
        if rol == "cliente" and re.match(r"^/ventas/\d+/comprobante(\.pdf)?$", ruta):
            consulta = [(k, v) for k, v in parse_qsl(request.url.query) if k not in ("rol", "usuario_id")]
            consulta += [("rol", "cliente"), ("usuario_id", str(usuario["id"]))]
            request.scope["query_string"] = urlencode(consulta).encode()

        request.state.usuario = usuario
        return await call_next(request)
