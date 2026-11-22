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

import re
import smtplib
import ssl
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
NOMBRE_NEGOCIO = "Caja Registradora Inteligente"

_CORREO_VALIDO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class CorreoError(Exception):
    """No se pudo enviar el correo (no esta configurado, no hay conexion, clave incorrecta...)."""


def correo_configurado() -> bool:
    """True si hay servidor SMTP configurado."""
    return bool(SMTP_HOST)


def _remitente() -> str:
    direccion = SMTP_REMITENTE or SMTP_USER
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
