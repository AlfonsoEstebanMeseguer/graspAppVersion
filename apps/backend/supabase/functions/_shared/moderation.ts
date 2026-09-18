// Los efectos de bloquear y de reportar (§2.5, §2.6, RN-22, RN-23, RN-25).
//
// DOS MITADES, y la separación importa: `resolveModeration` es **pura** —decide QUÉ hay que
// escribir, sin red ni Postgres, y es la que tienen los 10 tests—; `loadModerationState` y
// `applyModeration` hablan con la base y reciben el cliente **por parámetro** (patrón de
// `reconcile.ts`). Están en el mismo fichero porque `block-create` y `report-create` comparten el
// 90%, y sobre todo porque el ORDEN de las escrituras es una garantía de seguridad ante reintentos:
// duplicarlo en dos handlers sería duplicar un razonamiento, que es lo peor que se puede duplicar.
//
// ALCANCE DELIBERADO — «lógica sencilla, no completa» (decisión 6 del plan). Aquí está la
// persistencia y la propagación que las reglas ya describen. NO están, y cada una con su línea en
// `docs/pending-messaging.md`: la justificación del reporte, la cola de moderación, las sanciones y
// la reputación — la Fase 10 entera. Desbloquear (ADR 0027) SÍ está: es `deleteBlock`, lo dispara
// `block-remove`, y su puerta de entrada es `Perfil → Privacidad → Usuarios bloqueados`.
//
// DOS COSAS QUE NO SE HACEN Y NO SON OLVIDOS:
//
//   · **No se corta ningún follow**, en ninguna dirección, y desde el ADR 0028 (2026-08-30) eso es
//     una decisión CERRADA y no un pendiente. Cortarlo es OBSERVABLE: si A bloquea a B y B deja de
//     seguir a A de golpe, B lo nota. Un follow que sobrevive es inocuo porque el bloqueado no puede
//     actuar. Y desde que `block-remove` existe (ADR 0027) hay un segundo motivo, más fuerte:
//     cortarlos haría que un acto REVERSIBLE dejara un daño PERMANENTE, porque desbloquear no
//     podría restaurarlos — no quedaría de dónde. El test que fija la forma de `ModerationEffects`
//     está ahí para que añadir un `deleteFollows` rompa algo a propósito.
//   · **No se toca NADA del lado del bloqueado**: ni su `hidden`, ni su `cleared_at`, ni sus
//     mensajes. Conserva la conversación entera con el input inerte y el texto neutro (RN-23); lo
//     que se le niega es escribir, no ver.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { AppError } from "./http.ts";

export type ModerationAction = "block" | "report" | "unblock";

export interface ModerationContext {
  action: ModerationAction;
  /** Quien bloquea o reporta. */
  actorId: string;
  /** El bloqueado o reportado. */
  targetId: string;
  /** Si ya existe la fila `blocks (actorId, targetId)`. */
  alreadyBlocked: boolean;
  /** La conversación del par, si existe. `null` si nunca han hablado (se bloquea desde un perfil). */
  conversationId: string | null;
  now: Date;
}

/**
 * Una escritura sobre `conversation_states`.
 *
 * El `userId` viaja explícito, igual que en `messaging-actions.ts`, para que un test pueda recorrer
 * las acciones y comprobar que ninguna escribe en la fila del bloqueado. Si el tipo solo pudiera
 * expresar «el actor», RN-23 sería cierto por construcción pero **invisible**, y quien mañana
 * añadiera una escritura al otro lado no encontraría ningún test en su camino.
 */
export interface ModerationStateWrite {
  userId: string;
  patch: { hidden: boolean };
}

export interface ModerationEffects {
  /** `false` si ya estaba bloqueado: la fila no se duplica. */
  insertBlock: boolean;
  /**
   * ADR 0027. `false` si no había fila que borrar: desbloquear a quien no estaba bloqueado es un
   * no-op con 200, no un error, porque es lo que hace seguro el reintento.
   *
   * NO existe una lápida ni una columna `unblocked_at`: la fila se borra de verdad. Nadie lee ese
   * dato hoy —ni pantalla, ni Edge Function, ni moderación, que es Fase 10 entera— y el invariante
   * de minimización es explícito (Art. 5.1.c).
   */
  deleteBlock: boolean;
  stateWrites: ModerationStateWrite[];
  /** Solo en `report`. Un reporte es un evento, no un estado. */
  insertReport: boolean;
}

export function resolveModeration(ctx: ModerationContext): ModerationEffects {
  if (ctx.actorId === ctx.targetId) {
    throw new AppError(400, "invalid_input", "No puedes bloquearte ni reportarte a ti mismo", {
      field: "target_id",
    });
  }

  // --- ADR 0027: desbloquear. Es la única acción que NO propaga nada.
  //
  // No toca `conversation_states` a propósito: al bloquear, RN-22 puso `hidden = true` solo en el
  // lado del bloqueador, y ese mismo `hidden` lo pone también «Eliminar historial» (RN-27).
  // Ponerlo a `false` aquí desharía un archivado que la persona pudo hacer aparte y por otro
  // motivo. La conversación reaparece sola en cuanto alguno escriba: el trigger
  // `direct_messages_delivery` ya quita el `hidden`.
  //
  // Y no restaura ningún follow, porque bloquear nunca cortó ninguno (decisión 6).
  if (ctx.action === "unblock") {
    return {
      insertBlock: false,
      deleteBlock: ctx.alreadyBlocked,
      stateWrites: [],
      insertReport: false,
    };
  }

  return {
    insertBlock: !ctx.alreadyBlocked,
    deleteBlock: false,

    // RN-22: archiva la conversación, y SOLO la del que bloquea.
    //
    // NO depende de `alreadyBlocked`, y eso se aparta de la letra del plan («la segunda no duplica
    // fila ni vuelve a archivar»). El motivo es que las dos escrituras del bloqueo —la fila de
    // `blocks` y este `hidden`— NO comparten transacción: PostgREST son dos llamadas. Existe por
    // tanto un fallo a medias, con la fila puesta y la conversación sin archivar.
    //
    // Si el rearchivado dependiera de `alreadyBlocked`, ese estado sería ABSORBENTE: ninguna llamada
    // posterior lo arreglaría nunca, porque todas verían el bloqueo ya puesto. Volver a poner
    // `hidden = true` sobre algo que ya lo está no tiene ningún efecto observable, así que no se
    // pierde nada de la idempotencia que el plan pedía y se gana que un reintento REPARE.
    //
    // Por eso además el handler devuelve 500 —no 200— si la segunda escritura falla: es lo que hace
    // que el cliente reintente y la reparación llegue a ocurrir.
    stateWrites: ctx.conversationId === null
      ? []
      : [{ userId: ctx.actorId, patch: { hidden: true } }],

    // RN-25: reportar ejecuta el mismo bloqueo y además registra. Un reporte es un EVENTO, no un
    // estado: reportar a alguien ya bloqueado sigue dejando constancia, porque dos reportes son dos
    // hechos que la cola de moderación de la Fase 10 querrá ver por separado.
    insertReport: ctx.action === "report",
  };
}

// =================================================================================================
// LO QUE HABLA CON LA RED — el cliente entra por parámetro (patrón de `reconcile.ts`)
//
// Vive aquí y no en cada handler porque `block-create` y `report-create` comparten el 90%, y sobre
// todo porque **el ORDEN de las escrituras es la garantía ante reintentos**: duplicarlo en dos
// ficheros es duplicar un razonamiento de seguridad, que es la peor cosa que se puede duplicar.
// =================================================================================================

export interface ModerationState {
  targetExists: boolean;
  alreadyBlocked: boolean;
  /** La conversación del par, si existe. Se puede bloquear sin haber hablado nunca. */
  conversationId: string | null;
}

/** El par ordenado de `conversations` (`user_a_id < user_b_id`). */
function orderedPair(x: string, y: string): [string, string] {
  return x < y ? [x, y] : [y, x];
}

export async function loadModerationState(
  service: SupabaseClient,
  actorId: string,
  targetId: string,
): Promise<ModerationState> {
  const [userA, userB] = orderedPair(actorId, targetId);

  const [targetRes, blockRes, convRes] = await Promise.all([
    service.from("profiles").select("user_id").eq("user_id", targetId).maybeSingle(),
    service
      .from("blocks")
      .select("blocker_id")
      .eq("blocker_id", actorId)
      .eq("blocked_id", targetId)
      .maybeSingle(),
    service
      .from("conversations")
      .select("id")
      .eq("user_a_id", userA)
      .eq("user_b_id", userB)
      .maybeSingle(),
  ]);

  const failure = targetRes.error ?? blockRes.error ?? convRes.error;
  if (failure) {
    throw new AppError(500, "internal_error", "No se pudo cargar el estado de moderación", {
      cause: failure.message,
    });
  }

  return {
    targetExists: targetRes.data !== null,
    alreadyBlocked: blockRes.data !== null,
    conversationId: (convRes.data?.id as string | undefined) ?? null,
  };
}

/**
 * Aplica los efectos. EL ORDEN NO ES INDIFERENTE, y es lo que hace seguro el reintento:
 *
 *   1. **La fila de `blocks` primero.** Es la mitad PROTECTORA (RN-24: el bloqueado ya no puede
 *      escribir ni solicitar seguimiento). Si algo falla después, lo que queda hecho es lo que
 *      protege; lo que falta es archivar, que es cosmético.
 *   2. **El archivado después**, y sin depender de `alreadyBlocked`, para que un reintento lo repare.
 *   3. **La fila de `reports` la última.** Si fuera la primera, un fallo en el bloqueo devolvería
 *      500, el cliente reintentaría y el reporte quedaría registrado DOS veces.
 *
 * Y por eso cualquier fallo aquí devuelve 500 y no un 200 optimista: es el 500 el que provoca el
 * reintento que repara. Un 200 dejaría el bloqueo a medias para siempre.
 *
 * Las tres escrituras NO comparten transacción —PostgREST son tres llamadas—, así que la atomicidad
 * real exigiría una función SQL. Se acepta a sabiendas: el orden de arriba deja el peor caso en
 * «protegido pero sin archivar», que el siguiente intento arregla.
 */
export async function applyModeration(
  service: SupabaseClient,
  ctx: ModerationContext,
  effects: ModerationEffects,
  reportConversationId: string | null,
): Promise<void> {
  // ADR 0027. Va PRIMERO por la misma razón por la que `insertBlock` va primero en el bloqueo: es
  // la escritura que produce el efecto que el usuario pidió. Aquí no hay segunda escritura que
  // ordenar —desbloquear no propaga nada—, así que el orden es trivial; se deja explícito para que
  // quien añada un efecto mañana tenga que decidir dónde ponerlo en vez de heredarlo por azar.
  if (effects.deleteBlock) {
    const { error } = await service
      .from("blocks")
      .delete()
      .eq("blocker_id", ctx.actorId)
      .eq("blocked_id", ctx.targetId);

    if (error) {
      throw new AppError(500, "internal_error", "No se pudo desbloquear", { cause: error.message });
    }
  }

  if (effects.insertBlock) {
    // `on conflict do nothing`: dos peticiones cruzadas no deben dar un 500 por la PK.
    const { error } = await service
      .from("blocks")
      .upsert(
        { blocker_id: ctx.actorId, blocked_id: ctx.targetId },
        { onConflict: "blocker_id,blocked_id", ignoreDuplicates: true },
      );

    if (error) {
      throw new AppError(500, "internal_error", "No se pudo bloquear", { cause: error.message });
    }
  }

  for (const write of effects.stateWrites) {
    // El `eq('user_id', ...)` va explícito aunque el test fije que siempre es el actor: es la última
    // barrera si algún día alguien devolviera aquí una escritura del otro lado (RN-23).
    const { error } = await service
      .from("conversation_states")
      .update(write.patch)
      .eq("conversation_id", ctx.conversationId!)
      .eq("user_id", write.userId);

    if (error) {
      throw new AppError(500, "internal_error", "No se pudo archivar la conversación", {
        cause: error.message,
      });
    }
  }

  if (effects.insertReport) {
    const { error } = await service.from("reports").insert({
      reporter_id: ctx.actorId,
      reported_id: ctx.targetId,
      conversation_id: reportConversationId,
    });

    if (error) {
      throw new AppError(500, "internal_error", "No se pudo registrar el reporte", {
        cause: error.message,
      });
    }
  }
}
