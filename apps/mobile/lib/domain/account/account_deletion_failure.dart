/// Motivos por los que un intento de borrar la cuenta puede fallar.
///
/// El dominio expone la *causa*, no el texto: la copia en castellano vive en
/// la capa de presentación (`accountDeletionFailureMessage`), igual que
/// [AuthFailureKind] — traducir la app no debe obligar a tocar el dominio.
enum AccountDeletionFailureKind {
  /// `400 invalid_input`: falta la contraseña o la frase de confirmación no
  /// es la exigida. La hoja ya bloquea el envío hasta que las dos son
  /// válidas, así que esto solo debería llegar aquí por una carrera rara
  /// (p. ej. limpiar los campos entre que se habilita el botón y se pulsa).
  invalidInput,

  /// `401 invalid_credentials`: la contraseña no es correcta. Recuperable —
  /// no cierra sesión ni navega, el usuario puede reintentar en la misma
  /// hoja.
  wrongPassword,

  /// `401 unauthorized`: el JWT de la sesión no es válido o falta.
  sessionExpired,

  /// `409 reauth_unavailable`: la cuenta no tiene correo asociado con el que
  /// reautenticar. El backend documenta que hoy no puede pasar (el alta
  /// siempre lleva email), pero el contrato lo contempla.
  reauthUnavailable,

  /// Fallo de red o servidor inalcanzable.
  network,

  /// `500 internal_error` o cualquier otra cosa; se conserva el mensaje
  /// original en [AccountDeletionFailure.rawMessage] para diagnóstico, nunca
  /// para enseñarlo (hallazgo H-A-02 de la auditoría de 2026-08-15: el
  /// cliente no debe pintar mensajes internos del backend).
  unknown,
}

/// Fallo de borrado de cuenta normalizado — mismo patrón que `AuthFailure`.
class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.kind, {this.rawMessage});

  final AccountDeletionFailureKind kind;

  /// Mensaje/código original del backend. Nunca se muestra tal cual al
  /// usuario.
  final String? rawMessage;

  @override
  String toString() => 'AccountDeletionFailure(${kind.name}, raw: $rawMessage)';
}
