import 'blocked_user.dart';

/// Contrato de bloqueo y reporte (`RN-22` a `RN-25`).
///
/// ## Desbloquear existe desde el ADR 0027
///
/// Hasta el 2026-08-28 este fichero decía, en mayúsculas, que aquí no había `unblock`: el bloqueo
/// era irreversible desde la app. Ya no lo es. La Edge Function se llama `block-remove` y **no** se
/// renombró `block-create` a `block-toggle`: un toggle esconde en qué dirección acabaste, y sobre
/// una operación cuyo efecto observable depende del estado previo eso es peor que dos nombres.
///
/// **El modal de desbloqueo está obligado a decir que la otra persona puede deducir que la habías
/// bloqueado** — es la única información con la que quien desbloquea decide.
abstract interface class ModerationRepository {
  /// Bloquea a [userId] (`block-create`).
  ///
  /// Efectos: fila en `blocks` (`RN-24`), y la conversación se archiva **solo del lado del
  /// bloqueador** (`RN-22`). **No toca nada del lado del bloqueado**, que conserva conversación,
  /// historial y `cleared_at` (`RN-23`), y **no corta ningún follow** en ninguna dirección:
  /// cortarlos es observable, y `RN-23` dice que el bloqueo no se revela nunca.
  ///
  /// Devuelve 200 tanto si bloqueó como si ya estaba bloqueado, **con el mismo cuerpo**:
  /// distinguirlos diría algo sobre el estado previo.
  Future<void> block(String userId);

  /// Reporta a [userId] y **ejecuta el mismo bloqueo** (`report-create`, `RN-25`).
  ///
  /// [conversationId] es opcional, y si viene **tiene que ser de quien reporta** — si no, 404. Es
  /// el enlace que un humano de la cola de moderación abriría para leer el contexto.
  ///
  /// **Reportar es un evento; bloquear es un estado.** Reportar dos veces deja dos filas en
  /// `reports` y **un solo** bloqueo.
  ///
  /// Versión mínima de la Fase 4: sin categoría, sin justificación, sin cola de moderación, sin
  /// reputación, sin sanciones y sin deshacer. Todo eso es Fase 10.
  Future<void> report(String userId, {String? conversationId});

  /// Deshace el bloqueo de [userId] (`block-remove`, ADR 0027).
  ///
  /// Devuelve sin error tanto si había bloqueo como si no: **200 en los dos casos**, que es lo que
  /// hace seguro el reintento tras un fallo de red.
  ///
  /// **No devuelve la conversación a tu bandeja.** Al bloquear, `RN-22` la archivó (`hidden`), y ese
  /// mismo `hidden` lo pone «Eliminar historial» (`RN-27`): restaurarlo a ciegas desharía un
  /// archivado hecho por otro motivo. Reaparece sola cuando alguno de los dos escriba.
  ///
  /// **No retira ningún reporte.** Si el bloqueo nació de `report-create`, la denuncia se queda.
  Future<void> unblock(String userId);

  /// La lista de a quién has bloqueado, de más reciente a más antigua.
  ///
  /// **Va por PostgREST directo, no por Edge Function**, y no es un atajo: `blocks` ya tiene su RLS
  /// (`blocks_read_own`) y `authenticated` ya tiene `select` sobre las tres columnas. Inventar un
  /// endpoint para leer algo cuyo `grant` está concedido es construir dos veces la misma barrera.
  Future<List<BlockedUser>> blockedUsers();
}
