// Enrutado de la conversación (§4.2, RN-08, RN-09, RN-10). PURA: sin red y sin Postgres — recibe el
// estado y devuelve a qué estado nace o se reutiliza el hilo.
//
// NO decide si se PUEDE enviar: eso es `messaging-limits.ts`. Aquí solo se decide QUÉ estado tiene
// la conversación. El handler llama primero a los límites y después a esto.

export type ConversationStatus = "pending" | "accepted" | "ignored";

export interface ExistingConversation {
  status: ConversationStatus;
  initiatorId: string;
}

export interface RoutingContext {
  senderId: string;
  recipientId: string;
  /** La conversación del par, si ya existe. El par es único, así que o hay una o no hay ninguna. */
  existing: ExistingConversation | null;
  /** **RN-09: esto es lo ÚNICO que decide el enrutado.** */
  recipientFollowsSender: boolean;
  /**
   * Irrelevante por RN-09, y se recibe a propósito para que se vea que se ignora.
   *
   * Es el error del §4.2 caso 3 — parece que seguir a alguien debería bastar para entrar en sus
   * Contactos, y no basta: seguir a otro es una decisión tuya, no suya. Lo que abre la puerta es que
   * el RECEPTOR ya mostrara interés siguiéndote.
   */
  senderFollowsRecipient: boolean;
}

export type RoutingDecision =
  | { kind: "create"; status: "pending" | "accepted"; initiatorId: string }
  | { kind: "reuse"; status: ConversationStatus; upgradedToAccepted: boolean };

export function routeConversation(ctx: RoutingContext): RoutingDecision {
  // --- No hay hilo: nace ahora, y es el ÚNICO momento en que se evalúa el enrutado (RN-10).
  if (ctx.existing === null) {
    return {
      kind: "create",
      // RN-09 como regla única. Los cuatro casos de la tabla del §4.2 colapsan en esta línea:
      // casos 1 y 4 → accepted; casos 2 y 3 → pending.
      status: ctx.recipientFollowsSender ? "accepted" : "pending",
      initiatorId: ctx.senderId,
    };
  }

  // --- Ya hay hilo. Nunca se crea un segundo: el par es único (índice `conversations_pair_key`),
  // que es lo que hace imposible el hilo duplicado de RN-08 aunque dos peticiones crucen.

  // RN-08: el otro escribió primero y quedó pendiente; contestarle es aceptar de hecho, así que la
  // conversación pasa a `accepted` y se fusiona en un solo hilo ordenado por fecha.
  if (ctx.existing.status === "pending" && ctx.existing.initiatorId === ctx.recipientId) {
    return { kind: "reuse", status: "accepted", upgradedToAccepted: true };
  }

  // RN-10: para todo lo demás el estado NO se recalcula. Un follow posterior no convierte una
  // pendiente en aceptada — ni siquiera si ahora el receptor sigue al emisor. Quien reanuda una
  // conversación es RN-17, y solo al ACEPTAR el follow (vive en `follow-toggle`).
  //
  // Y una `ignored` se queda `ignored`: escribir en ella no la resucita, ni con follow mutuo. Para
  // el emisor se pinta igual que una pendiente (RN-06), pero eso lo hace la proyección por
  // espectador — el estado real no se toca aquí.
  return { kind: "reuse", status: ctx.existing.status, upgradedToAccepted: false };
}
