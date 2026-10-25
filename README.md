# Sistema de ventas IA — versión web

Caja registradora inteligente: backend **FastAPI + MySQL** y frontend **Flutter web**.

Esta es la **versión para internet** (usuarios y administrador). No incluye la detección de
productos por cámara (YOLO + CLIP + FAISS); eso vive solo en la versión de escritorio del proyecto.

## Qué incluye

- **Administrador**: dashboard con estadísticas, ventas (historial y exportación a PDF/CSV),
  pedidos pendientes, categorías, catálogo, inventario (stock, stock mínimo y alertas),
  agregar productos y gestión de usuarios.
- **Cliente (usuario)**: catálogo de productos con existencias, estado de sus pedidos,
  descarga de comprobantes y perfil.
- Comprobantes y facturas en PDF, búsqueda de clientes por CI y autocompletado.

## Configuración

### 1. Base de datos (MySQL / MariaDB)
Crea la base `caja_registradora_ia` e importa `frontend/sql/datos_producto_categorias.sql`.

### 2. Backend
Las credenciales se leen de variables de entorno o de `backend/.env` (no se sube a Git).
Usa `backend/.env.example` como plantilla (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`,
`CORS_ORIGINS`).

```bash
pip install -r backend/requirements.txt
cd backend/modelo
uvicorn deteccionobjeto:app --host 0.0.0.0 --port 8000
```

### 3. Frontend
Por defecto apunta a `http://localhost:8000`. Para otra URL del backend:

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE=https://TU-BACKEND.onrender.com
```

## Despliegue en Render

**Backend (Web Service)**
- Build command: `pip install -r backend/requirements.txt`
- Start command: `cd backend/modelo && uvicorn deteccionobjeto:app --host 0.0.0.0 --port $PORT`
- Variables de entorno: las de `backend/.env.example` (la base MySQL debe ser accesible desde
  internet; Render no ofrece MySQL propio, usa uno externo).
- `CORS_ORIGINS`: la URL del frontend (o `*` mientras pruebas).

**Frontend (Static Site)**
- La web ya compilada (apuntando a `https://sistema-de-ventas-ia.onrender.com`) esta en `frontend_web/`.
- En Render: New -> Static Site -> este repositorio, rama `main`.
  - Build Command: `echo ok`
  - Publish Directory: `frontend_web`
- Si cambia la URL del backend, hay que volver a compilar y reemplazar `frontend_web/`:
  `flutter build web --release --dart-define=API_BASE=https://TU-BACKEND.onrender.com`
  y copiar el contenido de `frontend/build/web` a `frontend_web/`.

## Pruebas

En `tests/` hay scripts de caja negra contra la API (validaciones, integridad del historial,
autocompletado de clientes, exportación a PDF, descarga de comprobantes) con sus informes en PDF.
