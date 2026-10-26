"""
Validaciones de datos del cliente, sin dependencias pesadas (no importa YOLO
ni nada de deteccion). Mismos formatos que validarDocumento() del frontend
(frontend/lib/widgets/pago_dialog.dart).
"""

import re

TIPOS_DOCUMENTO = ("CI", "NIT", "EXTRANJERO")

# Formatos por tipo de documento (se comparan en mayusculas)
#   CI         : 5 a 10 digitos, complemento opcional (1234567-1A)
#   NIT        : 7 a 13 digitos
#   EXTRANJERO : DNI / pasaporte / carnet de extranjeria, 6 a 20 letras,
#                numeros o guion, con al menos un numero (AB123456, 12345678-K)
FORMATOS_DOCUMENTO = {
    "CI": (re.compile(r"^\d{5,10}(-\d[A-Z])?$"),
           "El CI debe tener de 5 a 10 digitos (complemento opcional, ej. 1234567-1A)."),
    "NIT": (re.compile(r"^\d{7,13}$"),
            "El NIT debe tener solo numeros (7 a 13 digitos)."),
    "EXTRANJERO": (re.compile(r"^(?=.*\d)[A-Z0-9][A-Z0-9\-]{4,18}[A-Z0-9]$"),
                   "El documento extranjero debe tener de 6 a 20 letras o numeros "
                   "e incluir al menos un numero."),
}

RE_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
RE_TELEFONO = re.compile(r"^[0-9+\s\-]{6,20}$")


def documento(valor, tipo):
    """Normaliza (mayusculas) y valida el documento segun su tipo."""
    tipo = (tipo or "").strip().upper()
    if tipo not in FORMATOS_DOCUMENTO:
        raise ValueError("Tipo de documento invalido. Usa: CI, NIT o EXTRANJERO.")
    valor = (valor or "").strip().upper()
    regex, mensaje = FORMATOS_DOCUMENTO[tipo]
    if not regex.match(valor):
        raise ValueError(mensaje)
    return valor, tipo


def email(valor):
    valor = (valor or "").strip().lower()
    if len(valor) > 100 or not RE_EMAIL.match(valor):
        raise ValueError("El correo no es valido.")
    return valor


def telefono(valor):
    valor = (valor or "").strip()
    if not RE_TELEFONO.match(valor):
        raise ValueError("El telefono no es valido (6 a 20 numeros).")
    return valor


def nombre(valor):
    valor = " ".join((valor or "").split())
    if len(valor) < 2:
        raise ValueError("Ingresa tu nombre.")
    if len(valor) > 100:
        raise ValueError("El nombre es demasiado largo (maximo 100).")
    return valor
