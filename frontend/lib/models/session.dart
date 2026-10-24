/// Sesion del usuario activo en memoria durante la ejecucion de la app.
class Session {
  Session._();

  static int?    usuarioId;
  static String? username;
  static String? rol;

  static bool get esAdmin   => rol == 'administrador';
  static bool get esCajero  => rol == 'cajero';
  static bool get esCliente => rol == 'cliente';
  static bool get iniciada  => rol != null;

  static void iniciar({required int id, required String u, required String r}) {
    usuarioId = id;
    username  = u;
    rol       = r;
  }

  static void cerrar() {
    usuarioId = null;
    username  = null;
    rol       = null;
  }
}