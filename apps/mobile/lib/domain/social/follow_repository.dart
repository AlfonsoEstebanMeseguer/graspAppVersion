import 'follow_edge.dart';

/// Contrato de los seguimientos (§6.2, `RN-13` a `RN-20`).
///
/// Las **escrituras** pasan todas por `follow-toggle`: `user_follows` no tiene ninguna policy de
/// escritura, y los contadores de `profiles` son territorio exclusivo del backend. Si el cliente
/// pudiera escribir la fila directamente, un `PATCH` suelto por PostgREST desincronizaría los
/// contadores.
///
/// Las **lecturas** sí van por PostgREST directo con el perfil incrustado — que es para lo que las
/// dos claves ajenas de `user_follows` apuntan a `profiles`. La policy
/// `user_follows_read_own_or_accepted` decide qué filas se ven.
abstract interface class FollowRepository {
  /// Quién sigue a [userId] (`status = 'accepted'`).
  Future<List<FollowEdge>> followers(String userId);

  /// A quién sigue [userId] (`status = 'accepted'`).
  Future<List<FollowEdge>> following(String userId);

  /// Las solicitudes **recibidas** y sin decidir (`RN-51`).
  ///
  /// Solo tienen sentido las propias: la policy únicamente deja ver las `pending` en las que uno
  /// participa, así que pedir las de otra persona devolvería una lista vacía, no un error.
  Future<List<FollowRequest>> pendingRequests();

  /// Aplica una de las cinco acciones de `follow-toggle`.
  ///
  /// Es idempotente **por forma, no por clave**: `request` sobre una relación que ya existe y
  /// `accept` sobre una ya aceptada son no-op con 200.
  ///
  /// Lanza `SocialFailure` con [SocialFailureKind.notFound] cuando no existe la relación, no existe
  /// el destino **o hay un bloqueo** — los tres casos con el mismo cuerpo, porque `RN-23` prohíbe
  /// que nada los distinga. **No se puede saber cuál de los tres fue, y es deliberado.**
  Future<FollowToggleResult> toggle(FollowAction action, String targetId);
}
