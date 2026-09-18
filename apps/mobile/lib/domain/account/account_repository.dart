/// Contrato de borrado de cuenta.
///
/// Va aparte de `AuthRepository` (login/registro/logout) y de
/// `ProfileRepository` (lectura/edición de datos) por la misma razón que
/// `AvatarRepository` va aparte de `ProfileRepository`: es la única dueña de
/// un invariante propio — aquí, que el borrado exige reautenticar con
/// contraseña **y** escribir la frase de confirmación, y que una vez que el
/// backend responde `200` la cuenta ya no existe en `auth.users` (hallazgo
/// H-SV-02 de la auditoría de 2026-08-15).
abstract interface class AccountRepository {
  /// Borra la cuenta del usuario autenticado.
  ///
  /// [password] reautentica al usuario contra el backend; [confirmationPhrase]
  /// es la frase que el usuario escribió a mano ("BORRAR MI CUENTA"). El
  /// backend la compara normalizada (`trim().toUpperCase()`), así que aquí se
  /// manda tal cual la escribió el usuario — no hace falta (ni se debe)
  /// normalizarla antes de mandarla.
  ///
  /// No cierra sesión por su cuenta: quien llama decide cuándo hacerlo (ver
  /// `AccountDeletionController`), una vez que sabe que el borrado salió
  /// bien.
  Future<void> deleteAccount({
    required String password,
    required String confirmationPhrase,
  });
}
