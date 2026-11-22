"""
Configuracion del backend leida desde backend/.env (python-dotenv).

Copia backend/.env.example como backend/.env y completa tus datos.
Las variables de entorno del sistema tienen prioridad sobre el archivo.
"""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = BACKEND_DIR / ".env"

load_dotenv(ENV_FILE)


def _obligatoria(nombre, permitir_vacia=False):
    valor = os.getenv(nombre)
    if valor is None or (not permitir_vacia and not valor.strip()):
        sys.exit(
            f"\n[CONFIG] Falta la variable {nombre} en {ENV_FILE}\n"
            f"         Copia backend/.env.example como backend/.env y completa tus datos.\n"
        )
    return valor.strip()


def _opcional(nombre, por_defecto):
    valor = os.getenv(nombre)
    return valor.strip() if valor and valor.strip() else por_defecto


# ── MySQL ──────────────────────────────────────────────────────
DB_HOST = _obligatoria("DB_HOST")
DB_PORT = _obligatoria("DB_PORT")
DB_USER = _obligatoria("DB_USER")
DB_PASSWORD = _obligatoria("DB_PASSWORD", permitir_vacia=True)
DB_NAME = _obligatoria("DB_NAME")

if not DB_PORT.isdigit():
    sys.exit(f"\n[CONFIG] DB_PORT debe ser un numero (valor actual: {DB_PORT!r}) en {ENV_FILE}\n")
DB_PORT = int(DB_PORT)

# ── Archivos (ruta relativa a backend/modelo) ─────────────────
IMAGENES_DIR = _opcional("IMAGENES_DIR", "imagenes_productos")

# ── API ────────────────────────────────────────────────────────
# Origenes permitidos separados por coma, o * para permitir todos
CORS_ORIGINS = [o.strip() for o in _opcional("CORS_ORIGINS", "*").split(",") if o.strip()]

# ── Correo para el segundo factor (HU-24 1290, correo.py) ─────
# Todas opcionales: sin SMTP_HOST el backend funciona igual, solo falla el envio de correos.
SMTP_HOST = _opcional("SMTP_HOST", "")
SMTP_PORT = _opcional("SMTP_PORT", "587")
SMTP_USER = _opcional("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "").strip()
SMTP_REMITENTE = _opcional("SMTP_REMITENTE", "")
SMTP_SEGURIDAD = _opcional("SMTP_SEGURIDAD", "starttls").lower()
SMTP_TIMEOUT = _opcional("SMTP_TIMEOUT", "10")

if not SMTP_PORT.isdigit():
    sys.exit(f"\n[CONFIG] SMTP_PORT debe ser un numero (valor actual: {SMTP_PORT!r}) en {ENV_FILE}\n")
if SMTP_SEGURIDAD not in ("starttls", "ssl", "ninguna"):
    sys.exit(f"\n[CONFIG] SMTP_SEGURIDAD debe ser starttls, ssl o ninguna (valor actual: {SMTP_SEGURIDAD!r}) en {ENV_FILE}\n")
if not SMTP_TIMEOUT.isdigit():
    sys.exit(f"\n[CONFIG] SMTP_TIMEOUT debe ser un numero de segundos (valor actual: {SMTP_TIMEOUT!r}) en {ENV_FILE}\n")
SMTP_PORT = int(SMTP_PORT)
SMTP_TIMEOUT = int(SMTP_TIMEOUT)
