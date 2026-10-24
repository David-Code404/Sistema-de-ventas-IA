"""
Genera el PDF del historial de ventas (reportlab) con la paleta de la app.

Columnas: N. de venta, fecha, hora, productos con sus cantidades, total,
metodo de pago y cajero.

INSTALACION:
    pip install reportlab
"""

import io
from datetime import datetime

from reportlab.lib import colors
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

NAVY = HexColor("#0F172A")
VERDE = HexColor("#34D399")
VERDE_TEXTO = HexColor("#047857")
BORDE = HexColor("#E2E8F0")
FONDO_FILA = HexColor("#F8FAFC")
GRIS = HexColor("#64748B")

NEGOCIO = "Caja Registradora IA"
ALTO_ENCABEZADO = 28 * mm
METODOS = {"efectivo": "Efectivo", "tarjeta": "Tarjeta", "qr": "QR"}

_normal = ParagraphStyle("normal", fontName="Helvetica", fontSize=8.5, leading=11)
_celda = ParagraphStyle("celda", parent=_normal, textColor=NAVY)
_titulo = ParagraphStyle("titulo", fontName="Helvetica-Bold", fontSize=18, textColor=NAVY, leading=22)
_sub = ParagraphStyle("sub", parent=_normal, textColor=GRIS, fontSize=9.5)


def _bs(valor):
    return f"Bs. {float(valor):.2f}"


def _escapar(texto):
    return str(texto).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def _encabezado(canvas, doc):
    """Banda superior con el nombre del negocio, el titulo y la fecha de generacion."""
    ancho, alto = landscape(A4)
    canvas.saveState()
    canvas.setFillColor(NAVY)
    canvas.rect(0, alto - ALTO_ENCABEZADO, ancho, ALTO_ENCABEZADO, stroke=0, fill=1)
    canvas.setFillColor(VERDE)
    canvas.rect(0, alto - ALTO_ENCABEZADO - 1.2 * mm, ancho, 1.2 * mm, stroke=0, fill=1)

    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica-Bold", 20)
    canvas.drawString(12 * mm, alto - 14 * mm, NEGOCIO)
    canvas.setFillColor(VERDE)
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawString(12 * mm, alto - 21 * mm, "HISTORIAL DE VENTAS")

    canvas.setFillColor(colors.white)
    canvas.setFont("Helvetica", 9)
    canvas.drawRightString(ancho - 12 * mm, alto - 14 * mm, "Fecha de generacion")
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawRightString(ancho - 12 * mm, alto - 21 * mm,
                           f"{doc.generado:%d/%m/%Y  %H:%M}")
    canvas.restoreState()


def _pie(canvas, doc):
    canvas.saveState()
    canvas.setFillColor(GRIS)
    canvas.setFont("Helvetica", 8)
    ancho, _ = landscape(A4)
    canvas.drawString(12 * mm, 8 * mm, f"{NEGOCIO}  -  Historial de ventas")
    canvas.drawRightString(ancho - 12 * mm, 8 * mm, f"Pagina {doc.page}")
    canvas.restoreState()


def _pagina(canvas, doc):
    _encabezado(canvas, doc)
    _pie(canvas, doc)


def generar_pdf(ventas):
    """ventas: lista de dicts con id, creado_en, total, metodo_pago, cajero e items."""
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=landscape(A4),
        leftMargin=12 * mm, rightMargin=12 * mm, topMargin=ALTO_ENCABEZADO + 8 * mm, bottomMargin=16 * mm,
        title="Historial de ventas", author=NEGOCIO,
    )

    doc.generado = datetime.now()
    total_general = sum(float(v["total"]) for v in ventas)
    elementos = [
        Paragraph(f"{len(ventas)} venta(s)  -  Total general: <b>{_bs(total_general)}</b>", _sub),
        Spacer(1, 6),
    ]

    filas = [["N.", "Fecha", "Hora", "Productos (cantidad x nombre)", "Total", "Metodo de pago", "Cajero"]]
    for v in ventas:
        fecha = v["creado_en"]
        productos = "<br/>".join(
            f"{int(i['cantidad'])} x {_escapar(i['nombre'])}" for i in v["items"]
        ) or "-"
        filas.append([
            Paragraph(str(v["id"]), _celda),
            Paragraph(f"{fecha:%d/%m/%Y}", _celda),
            Paragraph(f"{fecha:%H:%M:%S}", _celda),
            Paragraph(productos, _celda),
            Paragraph(f"<b>{_bs(v['total'])}</b>", _celda),
            Paragraph(METODOS.get(v["metodo_pago"], _escapar(v["metodo_pago"])), _celda),
            Paragraph(_escapar(v["cajero"] or "Sin registrar"), _celda),
        ])

    if len(filas) == 1:
        filas.append(["", "", "", Paragraph("No hay ventas para mostrar.", _celda), "", "", ""])

    # Ancho util: 297 - 24 = 273 mm
    tabla = Table(
        filas, repeatRows=1,
        colWidths=[14 * mm, 24 * mm, 20 * mm, 119 * mm, 28 * mm, 30 * mm, 38 * mm],
    )
    estilo = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, 0), 8.5),
        ("LINEBELOW", (0, 0), (-1, 0), 2, VERDE),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 1), (-1, -1), 0.4, BORDE),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    for n in range(2, len(filas), 2):
        estilo.append(("BACKGROUND", (0, n), (-1, n), FONDO_FILA))
    tabla.setStyle(TableStyle(estilo))
    elementos.append(tabla)

    doc.build(elementos, onFirstPage=_pagina, onLaterPages=_pagina)
    return buffer.getvalue()
