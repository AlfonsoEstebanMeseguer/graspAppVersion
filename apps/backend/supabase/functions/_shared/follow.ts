// Lógica pura de `follow-toggle`: recibe el estado y devuelve la transición. PURA — sin red, sin
// Postgres y sin reloj propio (`now` entra por parámetro, que es lo que permite testear los bordes
// de la ventana móvil sin esperar 24 h).
//
// Aquí NO se escribe nada: quien aplica la transición es el handler, con `service_role`. Esta
// separación es lo que permite fijar en tests las cinco reglas que se pierden con facilidad —
// RN-13, RN-15, RN-16, RN-20 y RN-24 — sin levantar una base de datos.
import { AppError } from "./http.ts";

/** RN-20: máx. 20 solicitudes de seguimiento al día, contador independiente del de mensajería. */
export const MAX_FOLLOW_REQUESTS_PER_DAY = 20;

/** Ventana móvil de 24 h, no "día natural": así no hay medianoche que regale cupo. */
export const FOLLOW_REQUEST_WINDOW_MS = 24 * 60 * 60 * 1000;

export type FollowAction = "request" | "accept" | "reject" | "unfollow" | "remove_follower";

export interface FollowRow {
  follower_id: string;
  followee_id: string;
  status: "pending" | "accepted";
}

export interface FollowContext {
  action: FollowAction;
  /** Quien llama, resuelto del JWT. Nunca del body. */
  actorId: string;
  targetId: string;
  /** La fila existente en la dirección que la acción necesita, o `null`. */
  existing: FollowRow | null;
  /** Hay bloqueo en CUALQUIERA de las dos direcciones (RN-24). */
  blocked: boolean;
  /** El perfil destino no existe. Se trata igual que un bloqueo — ver `rechazoOpaco`. */
  targetMissing?: boolean;
  /** Solicitudes del actor pendientes dentro de la ventana. Solo se mira en `request`. */
  requestsToday: number;
  /** La más antigua de esas solicitudes: da el `retry_at` exacto de RN-21. */
  oldestRequestAt: string | Date | null;
  now: Date;
}

export type FollowTransition =
  | { kind: "noop"; counterDelta: 0; resumesIgnoredConversation: false }
  | {
    kind: "insert";
    followerId: string;
    followeeId: string;
    counterDelta: 0;
    resumesIgnoredConversation: false;
  }
  | {
    kind: "accept";
    followerId: string;
    followeeId: string;
    counterDelta: 1;
    resumesIgnoredConversation: true;
  }
  | {
    kind: "delete";
    followerId: string;
    followeeId: string;
    counterDelta: 0 | -1;
    resumesIgnoredConversation: false;
  };

/**
 * EL RECHAZO OPACO — es RN-23, y por eso es una sola función y no dos mensajes parecidos.
 *
 * Un bloqueo no se revela «ni por texto ni por forma». Si rechazar por bloqueo devolviera algo
 * distinto de rechazar por cuenta inexistente, el bloqueado deduciría el bloqueo comparando las dos
 * respuestas — que es exactamente lo que la regla prohíbe, y §6.2 lo dice explícito para el tag:
 * «responde igual que si no existiera».
 *
 * Que sea una única función es la garantía: no hay dos literales que puedan divergir al editarlos.
 * Hay un test que compara los dos caminos campo a campo.
 *
 * Lo que NO se promete es indistinguibilidad temporal: el camino del bloqueo hace una consulta más.
 * Cerrar eso exigiría otro diseño y está fuera del alcance (Global Constraints del plan).
 */
function rechazoOpaco(): never {
  throw new AppError(404, "not_found", "No se ha encontrado esa cuenta");
}

function requireExisting(existing: FollowRow | null): FollowRow {
  if (existing === null) {
    throw new AppError(404, "not_found", "No existe esa relación de seguimiento");
  }
  return existing;
}

export function resolveFollowTransition(ctx: FollowContext): FollowTransition {
  const NOOP = {
    kind: "noop",
    counterDelta: 0,
    resumesIgnoredConversation: false,
  } as const;

  if (ctx.actorId === ctx.targetId) {
    throw new AppError(400, "invalid_input", "No puedes seguirte a ti mismo", { field: "target_id" });
  }

  switch (ctx.action) {
    case "request": {
      // El no-op va ANTES del bloqueo y del tope, y antes de mirar si el destino existe: si ya
      // hay relación, no hay nada que decidir. Y va antes del tope a propósito — si un duplicado
      // consumiera cupo, pulsar dos veces el botón costaría dos solicitudes.
      if (ctx.existing !== null) return NOOP;

      if (ctx.blocked || ctx.targetMissing) rechazoOpaco();

      if (ctx.requestsToday >= MAX_FOLLOW_REQUESTS_PER_DAY) {
        // RN-21: el límite concreto y CUÁNDO se recupera. El cupo vuelve cuando la solicitud más
        // antigua sale de la ventana móvil, no 24 h desde ahora — decir lo segundo haría esperar
        // de más y la cuenta atrás de la UI no cuadraría con el servidor.
        const oldest = ctx.oldestRequestAt === null ? null : new Date(ctx.oldestRequestAt);
        const retryAt = oldest && !Number.isNaN(oldest.getTime())
          ? new Date(oldest.getTime() + FOLLOW_REQUEST_WINDOW_MS)
          : new Date(ctx.now.getTime() + FOLLOW_REQUEST_WINDOW_MS);

        throw new AppError(
          422,
          "rate_limited",
          `Solo puedes enviar ${MAX_FOLLOW_REQUESTS_PER_DAY} solicitudes de seguimiento al día`,
          {
            limit: MAX_FOLLOW_REQUESTS_PER_DAY,
            window_hours: FOLLOW_REQUEST_WINDOW_MS / 3_600_000,
            retry_at: retryAt.toISOString(),
          },
        );
      }

      return {
        kind: "insert",
        followerId: ctx.actorId,
        followeeId: ctx.targetId,
        counterDelta: 0,
        resumesIgnoredConversation: false,
      };
    }

    case "accept": {
      const row = requireExisting(ctx.existing);
      if (row.status === "accepted") return NOOP;

      // RN-17 reanuda una conversación ignorada; NO levanta un bloqueo. Si hay bloqueo vigente,
      // aceptar no puede ser el camino por el que el bloqueado recupera acceso.
      if (ctx.blocked) rechazoOpaco();

      // RN-13: unidireccional. Se conserva la dirección original (solicitante → aceptante) y no se
      // devuelve ninguna segunda fila: el aceptante NO pasa a seguir al solicitante.
      // RN-14: tampoco se crea conversación — la transición no tiene forma de pedirlo.
      return {
        kind: "accept",
        followerId: row.follower_id,
        followeeId: row.followee_id,
        counterDelta: 1,
        resumesIgnoredConversation: true,
      };
    }

    case "reject": {
      const row = requireExisting(ctx.existing);
      // RN-16: se BORRA la fila, no se marca como rechazada. Un follow rechazado puede volver a
      // solicitarse — justo lo contrario que el primer mensaje (RN-07), que es terminal. Por eso
      // `user_follows.status` no tiene el valor 'rejected': no existiría estado que borrar.
      return {
        kind: "delete",
        followerId: row.follower_id,
        followeeId: row.followee_id,
        counterDelta: row.status === "accepted" ? -1 : 0,
        resumesIgnoredConversation: false,
      };
    }

    case "unfollow":
    case "remove_follower": {
      const row = requireExisting(ctx.existing);
      // Las dos borran la misma fila; se diferencian en quién la pide y, por tanto, en qué
      // dirección la busca el handler. Los contadores solo se deshacen si llegó a estar aceptada:
      // cancelar una solicitud pendiente no resta nada, porque nunca sumó.
      // RN-15: no se toca ninguna conversación — `resumesIgnoredConversation` es false y no hay
      // ningún otro campo por el que un efecto sobre conversaciones pudiera colarse.
      return {
        kind: "delete",
        followerId: row.follower_id,
        followeeId: row.followee_id,
        counterDelta: row.status === "accepted" ? -1 : 0,
        resumesIgnoredConversation: false,
      };
    }
  }
}
