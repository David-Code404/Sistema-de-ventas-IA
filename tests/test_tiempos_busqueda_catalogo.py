"""
Prueba de caja negra: mide el tiempo de respuesta del endpoint de
busqueda del catalogo (GET /productos) bajo distintos escenarios.

No mira el codigo interno del backend, solo mide cuanto tarda en
responder desde afuera, que es justo lo que pide la tarea
"Testear tiempos de respuesta de la busqueda en catalogo" (HU-05-170).

INSTALACION:
    pip install requests

Uso:
    python test_tiempos_busqueda_catalogo.py
"""

import statistics
import time

import requests

API_BASE = "http://localhost:8000"
REPETICIONES = 20  # veces que se repite cada escenario, para sacar un promedio confiable
UMBRAL_ACEPTABLE_MS = 300  # criterio de aceptacion: el promedio no deberia superar esto

ESCENARIOS = [
    ("Catalogo completo (sin filtros)", {}),
    ("Busqueda por nombre", {"nombre": "TaBueno"}),
    ("Busqueda por nombre parcial", {"nombre": "a"}),
    ("Filtro por rango de precio", {"precio_min": "1", "precio_max": "3"}),
    ("Filtro por categoria", {"categoria_id": "1"}),
    ("Combinacion de filtros", {"nombre": "a", "precio_min": "1", "categoria_id": "1"}),
]


def medir_escenario(nombre, parametros):
    tiempos_ms = []
    errores = 0

    for _ in range(REPETICIONES):
        inicio = time.perf_counter()
        try:
            respuesta = requests.get(f"{API_BASE}/productos", params=parametros, timeout=5)
            if respuesta.status_code != 200:
                errores += 1
                continue
        except requests.RequestException:
            errores += 1
            continue
        fin = time.perf_counter()
        tiempos_ms.append((fin - inicio) * 1000)

    if not tiempos_ms:
        print(f"  [{nombre}] TODAS las peticiones fallaron ({errores} errores)")
        return None

    promedio = statistics.mean(tiempos_ms)
    minimo = min(tiempos_ms)
    maximo = max(tiempos_ms)
    resultado = "APROBADO" if promedio <= UMBRAL_ACEPTABLE_MS else "FUERA DE UMBRAL"

    print(f"  [{nombre}]")
    print(f"    promedio: {promedio:.1f} ms | min: {minimo:.1f} ms | max: {maximo:.1f} ms | errores: {errores}")
    print(f"    resultado: {resultado} (umbral: {UMBRAL_ACEPTABLE_MS} ms)")
    return {"nombre": nombre, "promedio_ms": promedio, "min_ms": minimo, "max_ms": maximo, "resultado": resultado}


def main():
    print(f"Probando {API_BASE}/productos con {REPETICIONES} repeticiones por escenario...\n")

    resultados = []
    for nombre, parametros in ESCENARIOS:
        resultado = medir_escenario(nombre, parametros)
        if resultado:
            resultados.append(resultado)
        print()

    print("=" * 60)
    print("RESUMEN")
    print("=" * 60)
    for r in resultados:
        print(f"{r['nombre']:<40} {r['promedio_ms']:>7.1f} ms  {r['resultado']}")


if __name__ == "__main__":
    main()
