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
