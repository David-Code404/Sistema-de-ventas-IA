"""
API liviana de la tienda en linea: catalogo, cuentas de clientes y pedidos.
Arranca sin cargar YOLO, CLIP ni torch, para desplegarla sola en la nube.

    cd backend/modelo
    uvicorn app_tienda:app --host 0.0.0.0 --port 8000

La API completa (con deteccion) sigue siendo deteccionobjeto:app, que incluye
estas mismas rutas.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import config
import rutas_cuentas
import rutas_pedidos
import rutas_tienda

app = FastAPI(title="Caja Registradora IA - Tienda en linea")

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.CORS_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(rutas_cuentas.router)
app.include_router(rutas_tienda.router)
app.include_router(rutas_pedidos.router)


@app.get("/salud")
def salud():
    return {"estado": "ok", "api": "tienda"}
