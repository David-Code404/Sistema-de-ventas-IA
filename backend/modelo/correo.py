"""
HU-24 - Tarea 1290: envio de correos (segundo factor por correo). No importa YOLO ni nada de deteccion.

Metodo elegido para el segundo factor: codigo de un solo uso enviado por CORREO (ver backend/segundo_factor.md).
Este modulo solo sabe ENVIAR el correo por SMTP; la generacion, expiracion y uso unico del codigo
son la tarea 1310 y la pantalla donde se escribe el codigo es la tarea 1300.

Configuracion (backend/.env, ver .env.example): SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASSWORD,
SMTP_REMITENTE y SMTP_SEGURIDAD. Si SMTP_HOST esta vacio el correo NO esta configurado y enviar_correo()
lanza CorreoError con un mensaje claro (el backend sigue funcionando; solo falla el envio).

Prueba de la configuracion:   python probar_correo.py tu_correo@gmail.com
"""

import json
import re
import smtplib
import ssl
import urllib.error
import urllib.request
from email.message import EmailMessage
from email.utils import formataddr

import config

SMTP_HOST = config.SMTP_HOST
SMTP_PORT = config.SMTP_PORT
SMTP_USER = config.SMTP_USER
SMTP_PASSWORD = config.SMTP_PASSWORD
SMTP_REMITENTE = config.SMTP_REMITENTE
SMTP_SEGURIDAD = config.SMTP_SEGURIDAD          # "starttls" (587), "ssl" (465) o "ninguna" (solo pruebas locales)
SMTP_TIMEOUT = config.SMTP_TIMEOUT
BREVO_API_KEY = config.BREVO_API_KEY            # si tiene valor, el correo sale por la API de Brevo (HTTPS)
BREVO_REMITENTE = config.BREVO_REMITENTE
BREVO_URL = "https://api.brevo.com/v3/smtp/email"
NOMBRE_NEGOCIO = "Caja Registradora Inteligente"

_CORREO_VALIDO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class CorreoError(Exception):
    """No se pudo enviar el correo (no esta configurado, no hay conexion, clave incorrecta...)."""


def correo_configurado() -> bool:
    """True si hay Brevo (API) o un servidor SMTP configurado."""
    return bool(BREVO_API_KEY or SMTP_HOST)


def _remitente() -> str:
    direccion = (BREVO_REMITENTE if BREVO_API_KEY else "") or SMTP_REMITENTE or SMTP_USER
    if not direccion:
        raise CorreoError("Falta SMTP_REMITENTE (o SMTP_USER) en backend/.env: es la direccion desde la que se envia.")
    return formataddr((NOMBRE_NEGOCIO, direccion))


def enviar_correo(destino: str, asunto: str, texto: str) -> None:
    """
    Envia un correo de texto a `destino`. Lanza ValueError si el destino no es un correo valido y
    CorreoError si el envio falla (con un mensaje que explica que revisar).
    """
    destino = (destino or "").strip()
    if not _CORREO_VALIDO.match(destino) or len(destino) > 120:
        raise ValueError("El correo de destino no es valido.")
    if not correo_configurado():
        raise CorreoError("El envio de correos no esta configurado: completa las variables SMTP_* en backend/.env "
                          "(ver .env.example y backend/segundo_factor.md).")

    if BREVO_API_KEY:
        return _enviar_por_brevo(destino, asunto, texto)

    mensaje = EmailMessage()
    mensaje["From"] = _remitente()
    mensaje["To"] = destino
    mensaje["Subject"] = asunto
    mensaje.set_content(texto, charset="utf-8")

    try:
        if SMTP_SEGURIDAD == "ssl":
            servidor = smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=SMTP_TIMEOUT, context=ssl.create_default_context())
        else:
            servidor = smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=SMTP_TIMEOUT)
        with servidor:
            servidor.ehlo()
            if SMTP_SEGURIDAD == "starttls":
                servidor.starttls(context=ssl.create_default_context())
                servidor.ehlo()
            if SMTP_USER:
                servidor.login(SMTP_USER, SMTP_PASSWORD)
            servidor.send_message(mensaje)
    except smtplib.SMTPAuthenticationError:
        raise CorreoError("El servidor de correo rechazo el usuario o la clave (SMTP_USER / SMTP_PASSWORD). "
                          "Con Gmail hay que usar una «contrasena de aplicacion», no la clave normal.")
    except smtplib.SMTPRecipientsRefused:
        raise CorreoError("El servidor de correo no acepto la direccion de destino.")
    except (smtplib.SMTPException, OSError) as e:
        raise CorreoError(f"No se pudo conectar con el servidor de correo {SMTP_HOST}:{SMTP_PORT} ({e}).")


def _enviar_por_brevo(destino: str, asunto: str, texto: str) -> None:
    """Envio por la API de Brevo (HTTPS, puerto 443): funciona en hosting que bloquea SMTP, como Render."""
    remitente = (BREVO_REMITENTE or SMTP_REMITENTE or SMTP_USER).strip()
    if not remitente:
        raise CorreoError("Falta BREVO_REMITENTE en backend/.env: es el correo verificado en Brevo desde el que se envia.")
    cuerpo = json.dumps({
        "sender": {"name": NOMBRE_NEGOCIO, "email": remitente},
        "to": [{"email": destino}],
        "subject": asunto,
        "textContent": texto,
    }).encode("utf-8")
    peticion = urllib.request.Request(
        BREVO_URL, data=cuerpo, method="POST",
        headers={"api-key": BREVO_API_KEY, "content-type": "application/json", "accept": "application/json"})
    try:
        with urllib.request.urlopen(peticion, timeout=SMTP_TIMEOUT):
            return
    except urllib.error.HTTPError as e:
        try:
            detalle = json.loads(e.read().decode("utf-8")).get("message", "")
        except Exception:
            detalle = ""
        if e.code in (401, 403):
            raise CorreoError("Brevo rechazo la clave API (BREVO_API_KEY). Revisa que la copiaste completa.")
        if e.code == 400:
            raise CorreoError("Brevo no acepto el envio: verifica que el remitente (BREVO_REMITENTE) este validado "
                              f"en tu cuenta de Brevo. {detalle}".strip())
        raise CorreoError(f"Brevo respondio con error {e.code}. {detalle}".strip())
    except (urllib.error.URLError, OSError) as e:
        raise CorreoError(f"No se pudo conectar con Brevo ({e}).")


def enviar_codigo_verificacion(destino: str, codigo: str, minutos: int = 5) -> None:
    """Correo con el codigo de verificacion del inicio de sesion (el codigo lo genera la tarea 1310)."""
    texto = (
        f"Hola,\n\n"
        f"Tu codigo de verificacion para iniciar sesion en {NOMBRE_NEGOCIO} es:\n\n"
        f"        {codigo}\n\n"
        f"Es valido por {minutos} minutos y solo se puede usar una vez.\n"
        f"Si no fuiste tu quien intento iniciar sesion, ignora este correo y cambia tu contrasena.\n\n"
        f"{NOMBRE_NEGOCIO}\n"
    )
    enviar_correo(destino, f"Tu codigo de verificacion: {codigo}", texto)
