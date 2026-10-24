/// Configuracion del frontend. Aqui NO van contrasenas ni claves secretas:
/// todo lo que se compila en Flutter puede verlo cualquiera.
///
/// La URL del backend se cambia al compilar o ejecutar:
///   flutter run -d chrome --dart-define=API_BASE=http://192.168.1.10:8000
class AppConfig {
  AppConfig._();

  /// URL base del backend (FastAPI). Por defecto, desarrollo local.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8000',
  );
}
