"""
HU-24 - Tarea 1290: prueba rapida del envio de correos (la configuracion SMTP de backend/.env).

Uso (desde backend/modelo):
    python probar_correo.py tu_correo@gmail.com

Envia un correo de prueba con un codigo de ejemplo. Si algo falla, explica que revisar.
No toca la base de datos.
"""

import sys

import correo


def main():
    if len(sys.argv) != 2:
        print("Uso: python probar_correo.py tu_correo@gmail.com")
        return 2
    destino = sys.argv[1]
    if not correo.correo_configurado():
        print("El correo NO esta configurado. Completa BREVO_API_KEY o las variables SMTP_* en backend/.env "
              "(mira .env.example y backend/segundo_factor.md) y vuelve a probar.")
        return 1
    via = "Brevo (API)" if correo.BREVO_API_KEY else f"{correo.SMTP_HOST}:{correo.SMTP_PORT}"
    print(f"Enviando correo de prueba a {destino} por {via} ...")
    try:
        correo.enviar_codigo_verificacion(destino, "123456", minutos=5)
    except (correo.CorreoError, ValueError) as e:
        print(f"No se pudo enviar: {e}")
        return 1
    print("Listo: revisa la bandeja de entrada (y la carpeta de spam).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
