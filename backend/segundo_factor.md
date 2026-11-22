# Segundo factor de autenticacion (HU-24)

## Tarea 1290 - Metodo elegido: codigo de un solo uso por CORREO

| Opcion | Decision | Motivo |
|---|---|---|
| Codigo por correo | **Elegida** | No cuesta nada, no exige instalar otra app, funciona en la web y en el celular, el cliente ya tiene correo. |
| Codigo por SMS | Descartada | Cada SMS tiene costo y necesita un proveedor (Twilio, etc.); ademas no hay telefono de los usuarios del personal. |
| App autenticadora (TOTP) | Descartada por ahora | Exige que cada usuario instale y configure una app; puede sumarse mas adelante sin cambiar el resto. |

## Que hace la tarea 1290
- `backend/modelo/correo.py`: envia correos por SMTP (`enviar_correo`, `enviar_codigo_verificacion`).
  Si algo falla lanza `CorreoError` con un mensaje que explica que revisar.
- `backend/modelo/config.py` + `backend/.env.example`: variables `SMTP_*` **opcionales**. Sin `SMTP_HOST`
  el backend funciona igual; solo no se pueden enviar correos.
- `backend/modelo/probar_correo.py`: comprobar la configuracion.

## Como configurarlo (Gmail como ejemplo)
1. En la cuenta de Google activa la verificacion en 2 pasos y crea una **contrasena de aplicacion**
   (https://myaccount.google.com/apppasswords). No sirve la clave normal.
2. Copia `backend/.env.example` a `backend/.env` (si no existe) y completa:
   ```
   SMTP_HOST=smtp.gmail.com
   SMTP_PORT=587
   SMTP_USER=tunegocio@gmail.com
   SMTP_PASSWORD=la_contrasena_de_aplicacion
   SMTP_REMITENTE=tunegocio@gmail.com
   SMTP_SEGURIDAD=starttls
   ```
   `.env` esta en `.gitignore`: la clave nunca se sube al repositorio.
3. Prueba: `cd backend/modelo` y `python probar_correo.py tu_correo@gmail.com`.

## Tareas 1310 y 1330 - Como funciona
- **Obligatorio** para administrador y cajero en cada inicio de sesion. **Opcional** para el cliente: lo activa o
  desactiva desde "Verificacion en dos pasos" en su menu de cuenta (pide su contrasena para confirmar).
- Flujo: usuario + contrasena correctos -> el backend devuelve `requiere_2fa` y un `reto` (aun no hay sesion) ->
  envia un codigo de 6 digitos al correo -> el usuario lo escribe -> `POST /auth/2fa/verificar` devuelve el usuario.
- El codigo vale **5 minutos**, es de **un solo uso**, admite **5 intentos** y se puede reenviar cada 30 s (maximo 3
  envios por inicio de sesion). Solo se guarda su huella (sha256), nunca el codigo.
- Administrador/cajero sin correo: en su primer inicio de sesion el sistema les pide el correo y envia el codigo
  ahi (solo se puede registrar si aun no tienen uno). Despues pueden cambiarlo desde su cuenta con su contrasena.
- Cliente: el codigo llega al correo de su ficha (`clientes.email`) o a otro que elija al activarlo.
- Tablas nuevas `segundo_factor_usuario` y `codigos_2fa` (se crean solas; `migraciones/004_segundo_factor.sql`).
  No se modificaron `usuarios` ni `clientes`.
- Endpoints: `POST /auth/2fa/correo`, `/auth/2fa/reenviar`, `/auth/2fa/verificar`; `GET /auth/2fa/estado`;
  `PUT /auth/2fa/configuracion`. Se suma al bloqueo de la tarea 1320.
- **Importante:** si el correo (`SMTP_*`) no esta configurado, el segundo factor queda desactivado en el servidor
  para no dejar a nadie sin poder entrar. En cuanto se configura, pasa a ser obligatorio para el personal.
