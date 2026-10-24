"""
Prueba de caja negra: verifica las reglas de validacion del nombre de
categoria contra la API real (POST/PUT /categorias), sin mirar el
codigo interno. Corresponde a la tarea
"Testear validaciones de nombre de categoria" (HU-06-210).

Casos probados, basados en las reglas que SI estan implementadas en el
backend (ver deteccionobjeto.py, clase CategoriaIn):
  1. Nombre vacio -> debe rechazarse (422)
  2. Nombre solo con espacios -> debe rechazarse (422)
  3. Nombre de mas de 100 caracteres -> debe rechazarse (422)
  4. Nombre duplicado (ya existente) -> debe rechazarse (409)
  5. Nombre valido -> debe aceptarse (201), y se limpia despues de la prueba

INSTALACION:
    pip install requests

Uso:
    python test_validaciones_nombre_categoria.py
"""

import requests

API_BASE = "http://localhost:8000"


def crear_categoria(nombre, descripcion="prueba automatizada"):
    return requests.post(
        f"{API_BASE}/categorias",
        json={"nombre": nombre, "descripcion": descripcion},
        timeout=5,
    )


def eliminar_categoria(categoria_id):
    requests.delete(f"{API_BASE}/categorias/{categoria_id}", timeout=5)


def reporte(caso, esperado, respuesta):
    obtenido = respuesta.status_code
    ok = obtenido == esperado
    estado = "APROBADO" if ok else "FALLIDO"
    print(f"[{estado}] {caso}")
    print(f"    esperado: {esperado} | obtenido: {obtenido}")
    if not ok:
        print(f"    cuerpo de la respuesta: {respuesta.text[:200]}")
    return ok


def main():
    resultados = []

    # Caso 1: nombre vacio
    r = crear_categoria("")
    resultados.append(reporte("Nombre vacio debe rechazarse", 422, r))

    # Caso 2: nombre solo espacios
    r = crear_categoria("   ")
    resultados.append(reporte("Nombre solo con espacios debe rechazarse", 422, r))

    # Caso 3: nombre demasiado largo (101 caracteres)
    nombre_largo = "A" * 101
    r = crear_categoria(nombre_largo)
    resultados.append(reporte("Nombre de 101 caracteres debe rechazarse", 422, r))

    # Caso 4: nombre valido, se crea para poder probar el duplicado despues
    nombre_prueba = "Categoria de prueba automatizada"
    r = crear_categoria(nombre_prueba)
    ok_creacion = reporte("Nombre valido debe aceptarse", 201, r)
    resultados.append(ok_creacion)

    id_creado = None
    if ok_creacion:
        id_creado = r.json().get("id")

    # Caso 5: nombre duplicado (mismo nombre que el caso anterior)
    if id_creado is not None:
        r = crear_categoria(nombre_prueba)
        resultados.append(reporte("Nombre duplicado debe rechazarse", 409, r))
    else:
        print("[OMITIDO] Nombre duplicado (no se pudo crear la categoria base para comparar)")

    # Limpieza: borra la categoria de prueba para no dejar basura
    if id_creado is not None:
        eliminar_categoria(id_creado)
        print(f"\nCategoria de prueba (id={id_creado}) eliminada.")

    print("\n" + "=" * 50)
    total = len(resultados)
    aprobados = sum(1 for r in resultados if r)
    print(f"RESUMEN: {aprobados}/{total} casos aprobados")


if __name__ == "__main__":
    main()
