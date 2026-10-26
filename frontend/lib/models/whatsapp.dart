import '../widgets/abrir_enlace.dart';

/// Aviso al cliente por WhatsApp cuando su pedido esta listo (sin API: abre
/// WhatsApp Web o la app con el mensaje escrito y el cajero lo envia).
class WhatsApp {
  WhatsApp._();

  /// Codigo de pais para celulares escritos sin prefijo (Bolivia).
  static const codigoPais = '591';

  /// Abre el enlace. Reemplazable en pruebas.
  static void Function(String url) abrir = abrirEnlace;

  /// Numero en formato internacional sin "+" (ej. 59170011223) o null si no
  /// sirve para WhatsApp.
  ///   70011223 / 7001-1223 -> 59170011223 (celular boliviano: 8 digitos, 6 o 7)
  ///   +591 70011223        -> 59170011223
  ///   +54 9 11 1234 5678   -> 5491112345678 (con "+" se respeta el pais)
  static String? numero(String? telefono) {
    final t = (telefono ?? '').trim();
    final digitos = t.replaceAll(RegExp(r'\D'), '');
    if (t.startsWith('+')) {
      return digitos.length >= 8 && digitos.length <= 15 ? digitos : null;
    }
    if (digitos.length == 8 && RegExp(r'^[67]').hasMatch(digitos)) {
      return '$codigoPais$digitos';
    }
    if (digitos.length == 11 &&
        digitos.startsWith(codigoPais) &&
        RegExp(r'^[67]').hasMatch(digitos.substring(3))) {
      return digitos;
    }
    return null;
  }

  /// Mensaje de "pedido listo" con el detalle de productos.
  static String mensajePedidoListo(Map<String, dynamic> pedido) {
    final nombre = (pedido['cliente_nombre'] ?? '').toString().trim();
    final primerNombre = nombre.isEmpty ? '' : ' ${nombre.split(RegExp(r'\s+')).first}';
    final items = (pedido['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final total = double.tryParse('${pedido['total']}') ?? 0;
    return [
      'Hola$primerNombre, tu pedido #${pedido['id']}',
      'Con el detalle:',
      for (final it in items) '• ${it['cantidad']} x ${it['nombre']}',
      'está listo para recoger.',
      'Total: Bs. ${total.toStringAsFixed(2)}',
      '¡Te esperamos!',
    ].join('\n');
  }

  /// Enlace wa.me con el chat del cliente y el mensaje escrito, o null si el
  /// telefono no sirve.
  static String? enlacePedidoListo(Map<String, dynamic> pedido) {
    final n = numero(pedido['cliente_telefono']?.toString());
    if (n == null) return null;
    return 'https://wa.me/$n?text=${Uri.encodeComponent(mensajePedidoListo(pedido))}';
  }
}
