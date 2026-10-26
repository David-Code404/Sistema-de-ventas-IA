import 'package:web/web.dart' as web;

/// Abre el enlace en una pestana nueva (p. ej. WhatsApp Web).
void abrirEnlace(String url) {
  web.window.open(url, '_blank');
}
