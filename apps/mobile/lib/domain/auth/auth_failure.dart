/// Motivos por los que un intento de autenticación puede fallar.
///
/// El dominio expone la *causa*, no el texto: la copia en castellano vive en la
/// capa de presentación (`authFailureMessage`), de forma que traducir la app no
/// obligue a tocar el dominio.
enum AuthFailureKind {
  /// El email introducido no tiene forma de email.
  invalidEmail,

  /// Contraseña vacía, muy corta o no cumple requisitos mínimos.
  invalidPassword,

  /// Las contraseñas no coinciden (confirmación).
  passwordMismatch,

  /// Login con una cuenta que no existe. No se crea en silencio: el usuario
  /// debe pasar por Registro.
  accountNotFound,

  /// Registro con un identificador que ya tiene cuenta.
  accountAlreadyExists,

  /// Credenciales incorrectas (email/password no coinciden).
  invalidCredentials,

  /// Demasiados intentos. Coincide con el rate limiting del Bloque 1.
  rateLimited,

  /// El alta está deshabilitada en el proyecto (proveedor de email apagado o
  /// registros cerrados).
  ///
  /// Es una **mala configuración del backend**, no un error del usuario. Tiene
  /// causa propia porque los dos sitios donde caía antes mentían: `unknown`
  /// ("algo no ha ido bien") no dice nada, y `accountNotFound` ("no encontramos
  /// tu cuenta") manda a crear una cuenta que el servidor va a rechazar igual.
  signUpUnavailable,

  /// Fallo de red o servidor inalcanzable.
  network,

  /// Cualquier otra cosa; se conserva el mensaje original para diagnóstico.
  unknown,
}

/// Fallo de autenticación normalizado.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, {this.rawMessage});

  final AuthFailureKind kind;

  /// Mensaje original del proveedor. Nunca se muestra tal cual al usuario, pero
  /// es lo que se manda a Sentry.
  final String? rawMessage;

  @override
  String toString() => 'AuthFailure(${kind.name}, raw: $rawMessage)';
}
