/// Sesion del usuario activo en memoria durante la ejecucion de la app.
class Session {
  Session._();

  static int?    usuarioId;
  static String? username;
  static String? rol;

  /// Token de sesion que la API entrega al iniciar sesion.
  static String? token;

  /// Ficha del cliente (nombre, documento, telefono...) si el rol es cliente.
  static Map<String, dynamic>? cliente;

  static bool get esAdmin   => rol == 'administrador';
  static bool get esCajero  => rol == 'cajero';
  static bool get esCliente => rol == 'cliente';
  static bool get iniciada  => rol != null;

  static void iniciar({
    required int id,
    required String u,
    required String r,
    Map<String, dynamic>? datosCliente,
    String? tokenSesion,
  }) {
    token     = tokenSesion;
    usuarioId = id;
    username  = u;
    rol       = r;
    cliente   = datosCliente;
  }

  static void cerrar() {
    usuarioId = null;
    username  = null;
    rol       = null;
    cliente   = null;
    token     = null;
  }
}
