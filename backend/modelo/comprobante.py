"""
Genera el comprobante de venta en PDF (reportlab) con la paleta de la app.

INSTALACION:
    pip install reportlab
"""

import io

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

NAVY = HexColor("#0F172A")
VERDE = HexColor("#34D399")
VERDE_OSCURO = HexColor("#04241A")
VERDE_TEXTO = HexColor("#047857")
VERDE_SUAVE = HexColor("#ECFDF5")
BORDE = HexColor("#E2E8F0")
FONDO_TARJETA = HexColor("#F8FAFC")
GRIS = HexColor("#64748B")
GRIS_CLARO = HexColor("#94A3B8")
AMBAR = HexColor("#FBBF24")
AMBAR_SUAVE = HexColor("#FFFBEB")

ANCHO, ALTO = A4
M = 40
NEGOCIO = "Caja Registradora IA"
MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
METODOS = {"efectivo": "Efectivo", "tarjeta": "Tarjeta", "qr": "QR"}


def numero(venta):
    return f"CR-{venta['creado_en'].year}-{int(venta['id']):08d}"


def _bs(valor):
    return f"Bs. {float(valor):.2f}"


def _pie(c):
    c.setStrokeColor(BORDE)
    c.line(M, 52, ANCHO - M, 52)
    c.setFillColor(GRIS_CLARO)
    c.setFont("Helvetica", 9)
    c.drawCentredString(ANCHO / 2, 36, f"Gracias por su compra  -  {NEGOCIO}")


def _recortar(texto, maximo):
    texto = str(texto)
    return texto if len(texto) <= maximo else texto[: maximo - 3] + "..."


def _cabecera(c, atendido_por, factura=False):
    c.setFillColor(NAVY)
    c.rect(0, ALTO - 110, ANCHO, 110, stroke=0, fill=1)
    c.setFillColor(VERDE)
    c.rect(0, ALTO - 114, ANCHO, 4, stroke=0, fill=1)

    c.roundRect(M, ALTO - 83, 52, 52, 12, stroke=0, fill=1)
    c.setFillColor(VERDE_OSCURO)
    c.setFont("Helvetica-Bold", 22)
    c.drawCentredString(M + 26, ALTO - 65, "CR")

    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 24)
    c.drawString(M + 68, ALTO - 56, NEGOCIO)
    c.setFillColor(VERDE)
    c.setFont("Helvetica", 11)
    c.drawString(
        M + 68, ALTO - 75,
        "Comprobante de venta  -  Factura solicitada" if factura else "Comprobante de venta",
    )

    if atendido_por:
        c.setFillColor(GRIS_CLARO)
        c.setFont("Helvetica", 8)
        c.drawRightString(ANCHO - M, ALTO - 48, "ATENDIDO POR")
        c.setFillColor(white)
        c.setFont("Helvetica-Bold", 14)
        c.drawRightString(ANCHO - M, ALTO - 66, atendido_por)


def _tarjeta(c, x, y_top, ancho, alto, titulo, pares):
    c.setFillColor(FONDO_TARJETA)
    c.setStrokeColor(BORDE)
    c.roundRect(x, y_top - alto, ancho, alto, 10, stroke=1, fill=1)
    c.setFillColor(VERDE_TEXTO)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(x + 14, y_top - 20, titulo)
    y = y_top - 42
    for etiqueta, valor in pares:
        c.setFillColor(GRIS)
        c.setFont("Helvetica", 8)
        c.drawString(x + 14, y, etiqueta)
        c.setFillColor(NAVY)
        c.setFont("Helvetica-Bold", 10.5)
        c.drawString(x + 14, y - 12, valor)
        y -= 24


def _encabezado_tabla(c, y_top):
    c.setFillColor(NAVY)
    c.rect(M, y_top - 26, ANCHO - 2 * M, 26, stroke=0, fill=1)
    c.setFillColor(white)
    c.setFont("Helvetica-Bold", 8.5)
    base = y_top - 17
    c.drawString(M + 12, base, "N")
    c.drawString(M + 44, base, "DESCRIPCION")
    c.drawCentredString(M + 318, base, "CANT.")
    c.drawRightString(M + 410, base, "P. UNIT.")
    c.drawRightString(M + 503, base, "SUBTOTAL")
    return y_top - 26


def generar_pdf(venta, atendido_por=None):
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    c.setTitle(f"Comprobante {numero(venta)}")

    creado = venta["creado_en"]
    metodo = METODOS.get(venta["metodo_pago"], str(venta["metodo_pago"]).title())
    estado_venta = venta.get("estado")
    if estado_venta in ("pendiente", "listo"):
        metodo = "Pago al recoger"      # el pedido en linea todavia no se cobro
    total = float(venta["total"])

    factura = bool(venta.get("factura"))
    _cabecera(c, atendido_por, factura)

    c.setFillColor(GRIS)
    c.setFont("Helvetica", 9)
    c.drawString(M, ALTO - 150, "COMPROBANTE")
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 26)
    c.drawString(M, ALTO - 176, numero(venta))
    c.setFillColor(VERDE)
    c.rect(M, ALTO - 188, 40, 3, stroke=0, fill=1)
    c.setFillColor(GRIS)
    c.setFont("Helvetica", 10)
    c.drawString(
        M, ALTO - 208,
        f"{creado.day:02d} de {MESES[creado.month - 1]} de {creado.year}"
        f"     |     {creado.strftime('%I:%M %p')}",
    )

    c.setFillColor(VERDE_SUAVE)
    c.setStrokeColor(VERDE)
    c.roundRect(ANCHO - M - 120, ALTO - 184, 120, 30, 15, stroke=1, fill=1)
    c.setFillColor(VERDE_TEXTO)
    c.setFont("Helvetica-Bold", 12)
    c.drawCentredString(ANCHO - M - 60, ALTO - 173,
                        {"pendiente": "PEDIDO PENDIENTE", "listo": "LISTO PARA RECOGER"}.get(estado_venta, "PAGADO"))

    ancho_tarjeta = (ANCHO - 2 * M - 16) / 2
    alto_tarjeta = 112
    y_tarjetas = ALTO - 228
    nombre_cli = venta.get("cliente_nombre")
    doc_cli = venta.get("cliente_documento")
    if nombre_cli or doc_cli:
        contacto = "  |  ".join(
            x for x in (venta.get("cliente_email"), venta.get("cliente_telefono")) if x
        )
        tercero = (("Contacto", _recortar(contacto, 36)) if contacto
                   else ("Factura", "Solicitada" if factura else "No solicitada"))
        _tarjeta(c, M, y_tarjetas, ancho_tarjeta, alto_tarjeta, "DATOS DEL CLIENTE", [
            ("Nombre", _recortar(nombre_cli or "-", 34)),
            ("NIT / CI", doc_cli or "-"),
            tercero,
        ])
    else:
        _tarjeta(c, M, y_tarjetas, ancho_tarjeta, alto_tarjeta, "DATOS DE LA VENTA", [
            ("Venta N.", str(venta["id"])),
            ("Estado", "Finalizada"),
            ("Atendido por", atendido_por or "-"),
        ])
    pagos = [("Metodo de pago", metodo)]
    if venta["metodo_pago"] == "efectivo" and venta["monto_recibido"] is not None:
        pagos.append(("Monto recibido", _bs(venta["monto_recibido"])))
        pagos.append(("Cambio", _bs(venta["cambio"] or 0)))
    else:
        pagos.append(("Estado del pago", "Pendiente: se paga al recoger"
                      if estado_venta in ("pendiente", "listo")
                      else "Pago confirmado por el cajero"))
    _tarjeta(c, M + ancho_tarjeta + 16, y_tarjetas, ancho_tarjeta, alto_tarjeta,
             "INFORMACION DE PAGO", pagos)

    y = _encabezado_tabla(c, y_tarjetas - alto_tarjeta - 24)
    alto_fila = 28
    for n, item in enumerate(venta["items"], start=1):
        if y - alto_fila < 250:
            _pie(c)
            c.showPage()
            y = _encabezado_tabla(c, ALTO - 50)
        if n % 2 == 1:
            c.setFillColor(VERDE_SUAVE)
            c.rect(M, y - alto_fila, ANCHO - 2 * M, alto_fila, stroke=0, fill=1)
        base = y - 18
        c.setFillColor(VERDE_TEXTO)
        c.setFont("Helvetica-Bold", 9)
        c.drawString(M + 12, base, str(n))
        c.setFillColor(NAVY)
        c.setFont("Helvetica", 10)
        c.drawString(M + 44, base, str(item["nombre"])[:42])
        c.drawCentredString(M + 318, base, str(item["cantidad"]))
        c.drawRightString(M + 410, base, _bs(item["precio_unitario"]))
        c.setFont("Helvetica-Bold", 10)
        c.drawRightString(M + 503, base, _bs(item["subtotal"]))
        y -= alto_fila

    c.setStrokeColor(BORDE)
    c.line(M, y, ANCHO - M, y)

    if y - 190 < 60:
        _pie(c)
        c.showPage()
        y = ALTO - 50
    y -= 22

    c.setFillColor(FONDO_TARJETA)
    c.setStrokeColor(BORDE)
    c.roundRect(M, y - 62, 230, 62, 10, stroke=1, fill=1)
    c.setFillColor(GRIS)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(M + 14, y - 22, "METODO DE PAGO")
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 15)
    c.drawString(M + 14, y - 44, metodo.upper())

    c.setFillColor(VERDE)
    c.roundRect(ANCHO - M - 230, y - 62, 230, 62, 10, stroke=0, fill=1)
    c.setFillColor(VERDE_OSCURO)
    c.setFont("Helvetica-Bold", 8)
    c.drawString(ANCHO - M - 216, y - 22, "TOTAL")
    c.setFont("Helvetica-Bold", 26)
    c.drawRightString(ANCHO - M - 16, y - 46, _bs(total))
    y -= 62 + 22

    c.setFillColor(AMBAR_SUAVE)
    c.rect(M, y - 44, ANCHO - 2 * M, 44, stroke=0, fill=1)
    c.setFillColor(AMBAR)
    c.rect(M, y - 44, 4, 44, stroke=0, fill=1)
    c.setFillColor(HexColor("#92400E"))
    c.setFont("Helvetica-Bold", 9)
    c.drawString(M + 16, y - 18, "NOTA:")
    c.setFont("Helvetica", 9)
    if factura:
        c.drawString(M + 48, y - 18, "Factura solicitada. Este comprobante no tiene validez fiscal;")
        c.drawString(M + 16, y - 33, "la factura oficial se emite aparte. Conservalo como respaldo de tu compra.")
    else:
        c.drawString(M + 48, y - 18, "Comprobante de venta sin validez fiscal.")
        c.drawString(M + 16, y - 33, f"Conserva este comprobante como respaldo de tu compra en {NEGOCIO}.")

    _pie(c)
    c.save()
    return buf.getvalue()
