import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void descargarDesde(String url) {
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = '';
  web.document.body?.append(a);
  a.click();
  a.remove();
}

/// Guarda un archivo (por ejemplo un PDF) que ya se tiene en memoria.
void descargarBytes(Uint8List bytes, String nombre,
    {String tipo = 'application/pdf'}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: tipo));
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = nombre;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
