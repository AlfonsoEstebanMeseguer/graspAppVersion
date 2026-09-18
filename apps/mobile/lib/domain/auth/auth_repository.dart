/// Contrato de autenticación.
///
/// Las pantallas dependen de esta interfaz, nunca del cliente de Supabase
/// (skill `flutter-ui`, punto 1): así el día que cambie el proveedor de auth no
/// hay que tocar ninguna pantalla, y los tests pueden sustituirlo.
///
/// **No hay envío de correos ni de SMS.** Grasp no manda códigos de un solo
/// uso, magic links ni correos de confirmación: el alta crea la cuenta y abre
/// sesión en el mismo paso (ver `docs/decisions/0005-registro-sin-email.md`).
abstract interface class AuthRepository {
  /// Emite el usuario autenticado (`userId`) o `null` al cerrar sesión.
  Stream<String?> authStateChanges();

  /// Id del usuario actual, o `null` si no hay sesión.
  String? get currentUserId;

  /// Login con email + contraseña.
  Future<void> signInWithPassword({
    required String identifier,
    required String password,
  });

  /// Registro con email + contraseña + datos de perfil.
  ///
  /// Los datos de perfil viajan como metadata del alta; quien los escribe en
  /// `profiles`/`profiles_private` es el trigger `on_auth_user_created`.
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
    required DateTime birthDate,
    required String gender,
  });

  Future<void> signOut();
}
