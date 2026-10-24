import 'package:web/web.dart' as web;

void descargarDesde(String url) {
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = '';
  web.document.body?.append(a);
  a.click();
  a.remove();
}
