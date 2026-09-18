import 'package:flutter/foundation.dart';

/// **El texto del input inerte. Una sola constante, y es deliberado.**
///
/// Espejo Dart de `INPUT_NOTICE_QUOTA` en `_shared/messaging-view.ts`. Lo fija el
/// [ADR 0022](../../../../docs/decisions/0022-un-solo-texto-para-el-input-inerte.md), que resolvió
/// el choque entre `RN-21` (di qué límite y cuándo se recupera) y `RN-23` (que el bloqueo no se
/// distinga): **el mismo texto para el cupo agotado y para el bloqueo**. El literal
/// *«No puedes enviar mensajes a esta cuenta.»* que `RN-23` citaba está retirado.
///
/// Dart y Deno no pueden compartir una constante, así que
/// `test/domain/social/message_input_state_test.dart` compara ésta con la del backend leyendo el
/// `.ts`: si alguien edita una, el test se pone rojo. Es lo más parecido a "una sola constante"
/// que se puede tener cruzando dos lenguajes, y el ADR existe justo para evitar que diverjan.
const String kMessageInputNotice =
    'Podrás seguir escribiendo cuando esta persona acepte tu mensaje.';

/// Los estados posibles del input de la conversación (§9.2).
///
/// ## Por qué una `sealed class` y no cuatro booleanos sueltos
///
/// Con booleanos (`canSend`, `notice`, `messagesLeft`, `requestActions`) la pantalla puede pintar
/// combinaciones que no existen —«puedes escribir» **y** el aviso a la vez— y nada lo impide. Con
/// una jerarquía sellada, `switch` es exhaustivo: el compilador obliga a tratar los cuatro casos y
/// **no hay forma de expresar dos a la vez**.
///
/// ## Por qué son CUATRO variantes y el §9.2 tiene CINCO filas
///
/// Las filas 3 (cupo agotado) y 5 (bloqueado) del §9.2 son **idénticas campo a campo** en la
/// respuesta del backend — lo dice la tabla de `docs/api-contracts.md` y lo garantiza el tipo
/// `PublicSendBlockedReason` de `_shared/messaging-limits.ts`, que **no tiene variante para el
/// bloqueo**. No existe valor que el handler pueda serializar y que lo delate.
///
/// Darles dos variantes distintas en Dart exigiría que el cliente supiera algo que el backend se
/// niega a decirle. O sería código muerto imposible de construir —una invitación a que alguien lo
/// cablee más adelante por otra vía— o se rellenaría desde un canal lateral, que es exactamente la
/// fuga que `RN-23` prohíbe. Así que las dos filas comparten [MessageInputInert] **y ésa es la
/// garantía escrita en el tipo**, igual que en el backend.
///
/// (El plan de la Tarea 19 dice «los cinco estados»; se escribió el 2026-08-23, dos días antes de
/// que el ADR 0022 colapsara esas dos filas. Su motivo declarado —«impedir pintar *puedes
/// escribir* y el aviso de bloqueo a la vez»— lo cumplen estas cuatro.)
@immutable
sealed class MessageInputState {
  const MessageInputState();

  /// El estado de una conversación que **todavía no existe**: §9.2 fila 6, abrir chat desde
  /// Conectar. No hay `messaging-thread` que consultar, así que se construye aquí, y tiene que
  /// coincidir con lo que devolverá el backend en cuanto haya conversación.
  static const MessageInputState newConversation = MessageInputLimited(5);

  /// Interpreta el objeto `input` de `messaging-thread`.
  ///
  /// ## El orden de las ramas es una decisión de seguridad, no de estilo
  ///
  /// `request_actions` se mira **el primero**, antes que `can_send`.
  ///
  /// El motivo fue un oráculo de bloqueo real: la combinación `can_send: false` +
  /// `request_actions: true` era alcanzable —A manda solicitud a B y después bloquea a B—, y para
  /// una solicitud **recibida** un `can_send: false` **solo puede venir de un bloqueo** (el tope de
  /// `RN-01` se le aplica a quien pide entrar, no a quien contesta: `evaluateSendLimits` devuelve
  /// *PUEDE* en cuanto `existing.initiatorId === recipientId`, y lo único que se comprueba antes es
  /// el bloqueo). Si `can_send` ganara, B vería un input inerte donde otro ve las cuatro acciones.
  ///
  /// **Desde el 2026-08-26 el backend ya no lo emite** — `messaging-view.ts` devuelve esa fila
  /// constante ([ADR 0025](../../../../docs/decisions/0025-la-fila-4-del-input-se-emite-constante.md)),
  /// así que la combinación ya no llega. Esta guarda **se conserva a propósito**, como segunda
  /// capa: es barata, y si el backend regresara, la pantalla seguiría sin delatar nada.
  ///
  /// Lo cubre un test en `message_input_state_test.dart`.
  factory MessageInputState.fromJson(Map<String, dynamic> json) {
    if (json['request_actions'] == true) return const MessageInputAwaitingDecision();

    // Falla cerrado: si el campo falta o no es un booleano, no se deja escribir. Al revés —dejar
    // escribir ante la duda— produce un 422 que la persona no puede entender ni corregir.
    final bool canSend = json['can_send'] == true;
    if (!canSend) {
      final Object? notice = json['input_notice'];
      // Nunca una cadena vacía: un input inerte y mudo no le dice a nadie qué está pasando, y
      // `RN-21` obliga a explicarlo.
      final String text = notice is String && notice.trim().isNotEmpty
          ? notice
          : kMessageInputNotice;
      return MessageInputInert(text);
    }

    final Object? left = json['messages_left'];
    if (left is! int) return const MessageInputOpen();
    return MessageInputLimited(left);
  }

  /// Si la pantalla tiene que pintar un campo de texto **utilizable**.
  ///
  /// No sustituye al `switch`: la conversación necesita saber *qué* pintar (contador, aviso o las
  /// cuatro acciones), y eso solo sale de distinguir la variante.
  bool get canType => this is MessageInputOpen || this is MessageInputLimited;
}

/// §9.2 fila 1: conversación aceptada. Se escribe sin tope.
///
/// También cubre el hilo que **abrió la otra persona** y sigue pendiente: contestarle es aceptarlo
/// de hecho (`RN-08`), así que no se le aplica el tope de 5, que es de quien pide entrar.
final class MessageInputOpen extends MessageInputState {
  const MessageInputOpen();

  @override
  bool operator ==(Object other) => other is MessageInputOpen;

  @override
  int get hashCode => (MessageInputOpen).hashCode;

  @override
  String toString() => 'MessageInputOpen()';
}

/// §9.2 filas 2 y 6: solicitud propia todavía sin aceptar, con mensajes por gastar.
///
/// [messagesLeft] va de 5 a 1 — `RN-01`, «exactamente 5 mensajes… ni uno más, bajo ninguna
/// circunstancia». Al llegar a 0 el backend devuelve [MessageInputInert], no esta variante con
/// cero: el `0` sale del **veredicto** y no del contador, y esa diferencia es `RN-23` (ver
/// `remainingMessages` en `_shared/messaging-view.ts`).
final class MessageInputLimited extends MessageInputState {
  const MessageInputLimited(this.messagesLeft);

  final int messagesLeft;

  @override
  bool operator ==(Object other) =>
      other is MessageInputLimited && other.messagesLeft == messagesLeft;

  @override
  int get hashCode => Object.hash(MessageInputLimited, messagesLeft);

  @override
  String toString() => 'MessageInputLimited($messagesLeft)';
}

/// §9.2 filas 3 **y** 5: no se puede escribir. Cupo agotado o bloqueo, **indistinguibles**.
///
/// Que sea una sola variante es la mitad de `RN-23` que le toca al cliente. La otra mitad la pone
/// el backend, mandando el mismo cuerpo byte a byte en los dos casos.
///
/// **No añadir aquí un campo `reason`, `blocked` ni nada que separe los dos casos**: no hay dato
/// con el que rellenarlo, y el hueco invita a buscarlo por otro lado. Un test compara los dos
/// estados enteros justo para que ese campo no pueda aparecer sin ponerse en rojo.
///
/// Límite conocido y aceptado (ADR 0022): en una conversación **ya aceptada**, un input inerte es
/// en sí mismo una señal que ningún texto tapa. Cerrarlo exigiría otro diseño y queda fuera de la
/// Fase 4.
final class MessageInputInert extends MessageInputState {
  const MessageInputInert(this.notice);

  /// El texto que se enseña. En la práctica siempre [kMessageInputNotice] — es un campo y no una
  /// constante incrustada porque el texto lo manda el backend y el cliente lo muestra, no lo
  /// decide.
  final String notice;

  @override
  bool operator ==(Object other) =>
      other is MessageInputInert && other.notice == notice;

  @override
  int get hashCode => Object.hash(MessageInputInert, notice);

  @override
  String toString() => 'MessageInputInert($notice)';
}

/// §9.2 fila 4: solicitud **recibida** sin aceptar. El input se sustituye por las cuatro acciones
/// de `RN-04` — `Aceptar` / `Ignorar` / `Bloquear` / `Reportar`.
///
/// No lleva ningún dato: cualquier campo aquí sería un sitio donde colar el motivo por el que
/// `can_send` venía a `false`, que es justo lo que no puede llegar a la pantalla (ver
/// [MessageInputState.fromJson]).
final class MessageInputAwaitingDecision extends MessageInputState {
  const MessageInputAwaitingDecision();

  @override
  bool operator ==(Object other) => other is MessageInputAwaitingDecision;

  @override
  int get hashCode => (MessageInputAwaitingDecision).hashCode;

  @override
  String toString() => 'MessageInputAwaitingDecision()';
}
