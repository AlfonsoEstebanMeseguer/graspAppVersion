import '../../../../domain/account/account_deletion_failure.dart';

/// Copia en castellano de cada causa de fallo del borrado de cuenta.
///
/// Vive en presentación, no en el dominio, por la misma razón que
/// `authFailureMessage`: traducir la app no debe obligar a tocar la capa de
/// negocio. Nunca se enseña `AccountDeletionFailure.rawMessage` — es el
/// hallazgo H-A-02 de la auditoría de 2026-08-15 (el cliente pintaba
/// mensajes internos del backend).
String accountDeletionFailureMessage(AccountDeletionFailure failure) => switch (failure.kind) {
  AccountDeletionFailureKind.invalidInput =>
    'Revisa la contraseña y la frase de confirmación.',
  AccountDeletionFailureKind.wrongPassword =>
    'La contraseña no es correcta. Inténtalo de nuevo.',
  AccountDeletionFailureKind.sessionExpired =>
    'Tu sesión ha caducado. Cierra sesión, vuelve a entrar e inténtalo otra vez.',
  AccountDeletionFailureKind.reauthUnavailable =>
    'No podemos verificar tu contraseña ahora mismo. Escríbenos a soporte para borrar tu cuenta.',
  AccountDeletionFailureKind.network =>
    'No hemos podido conectar. Comprueba tu conexión e inténtalo otra vez.',
  AccountDeletionFailureKind.unknown =>
    'Algo no ha ido bien. Inténtalo de nuevo en unos segundos.',
};
